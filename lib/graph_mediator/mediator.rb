require 'aasm'

module GraphMediator
  # Instances of this class perform the actual mediation work on behalf of a
  # Proxy#mediated_transaction.
  class Mediator
    include AASM

    class IndexedHash < Hash
      attr_reader :index
      attr_reader :klass

      def initialize(*args, &block)
        @index = {}
        super
      end

      def <<(ar_instance, klass, changes)
        add_to_index(changes)
        case
          when ar_instance.new_record? then
            created_array = self[:_created] ||= []
            created_array << changes
          when ar_instance.destroyed? then
            destroyed_array = self[:_destroyed] ||= []
            destroyed_array << ar_instance.id
          else self[ar_instance.id] = changes
        end 
      end

      def add_to_index(changes)
        index.merge!(changes)
      end
    end
 
    class ChangesHash < IndexedHash
    
      def <<(ar_instance)
        raise(ArgumentError, "Expected an ActiveRecord::Dirty instance: #{ar_instance}") unless ar_instance.respond_to?(:changed?)
        klass = ar_instance.class.base_class
        changes = ar_instance.changes
        add_to_index(changes)
        klass_hash = self[klass] ||= IndexedHash.new
        klass_hash.<<(ar_instance, klass, changes)
        return self
      end

      # True if the given attribute was changed in root or a dependent.
      #
      # * attribute - symbol or string for attribute to lookup
      # * klass - optionally, restrict lookup to changes for a particular class.
      #
      # Shortcut:
      # changed_#{attribute}?
      # #{my_class}_changed_#{attribute}?
      #
      def attribute_changed?(attribute, klass = nil)
        (klass ? _class_hash(klass) : self).index.key?(attribute.to_s)
      end

      # True if all the passed attributes were changed in root or a dependent.
      def all_changed?(*attributes)
        attributes.all? { |a| attribute_changed?(a) }
      end

      # True if any of the passed attributes were changed in root or a
      # dependent.
      def any_changed?(*attributes)
        attributes.any? { |a| attribute_changed?(a) }
      end

      # True if a dependent of the given class was added.
      def added_dependent?(klass)
        _class_hash(klass).key?(:_created)
      end

      # True if a dependent of the given class was destroyed.
      def destroyed_dependent?(klass)
        _class_hash(klass).key?(:_destroyed)
      end

      # True if an existing dependent of the given class was updated.
      def altered_dependent?(klass)
        !_class_hash(klass).reject { |k,v| k == :_created || k == :_destroyed }.empty?
      end

      # True only if a dependent of the given class was added or destroyed. 
      def added_or_destroyed_dependent?(klass)
        added_dependent?(klass) || destroyed_dependent?(klass)
      end

# TODO this and altered_dependent may give false positive for empty change hashes (if a record is saved with no changes, there will be a +record_id+ => {} entry)
      # True if a dependent of the given class as added, destroyed or updated.
      def touched_any_dependent?(klass)
        !_class_hash(klass).empty?
      end

# TODO raise an error if class does not respond to method?  but what about general changed_foo? calls?  The point is that this syntax can give you false negatives, because changed_foo? will be false even foo isn't even an attribute -- misspelling an attribute can lead to difficult bugs.  This helper may not be a good idea...
      def method_missing(method)
        case method.to_s
          when /(?:(.*)_)?changed_(.*)\?/
          then
            klass = $1
            klass = klass.classify.constantize if klass
            attribute = $2
# XXX Don't define a method here, or you run into issues with Rails class
# reloading.  After the first call, you hold a reference to an old Class which
# will no longer work as a key in a new changes hash.
#            self.class.__send__(:define_method, method) do
              return attribute_changed?(attribute, klass) 
#            end
#            return send(method)
          else super       
        end
      end
      
      private

      def _class_hash(klass)
        self.fetch(klass.base_class, nil) || IndexedHash.new
      end 
    end

    # An instance of the root ActiveRecord object currently under mediation.
    attr_accessor :mediated_instance

    # Changes made to mediated_instance or dependents during a transaction.
    attr_accessor :changes

    # Tracks nested transactions
    attr_accessor :stack

    aasm_initial_state :idle
    aasm_state :idle
    aasm_state :mediating
    aasm_state :versioning
    aasm_state :disabled

    aasm_event :start do
      transitions :from => :idle, :to => :mediating
    end
    aasm_event :bump do
      transitions :from => :mediating, :to => :versioning
    end
    aasm_event :disable do
      transitions :from => :idle, :to => :disabled
    end
    aasm_event :done do
      transitions :from => [:idle, :mediating, :versioning, :disabled], :to => :idle
    end

    def initialize(instance)
      raise(ArgumentError, "Given instance has not been initialized for mediation: #{instance}") unless instance.kind_of?(GraphMediator)
      self.mediated_instance = instance
      self.changes = ChangesHash.new
      self.stack = []
    end

    # Mediation may be disabled at either the Class or instance level.
    # TODO - global module setting?
    def mediation_enabled?
      mediated_instance.mediation_enabled?
    end

    # The id of the instance we are mediating.  
    def mediated_id
      mediated_instance.try(:id)
    end

    # Record the ActiveRecord changes state of the current object.  This allows
    # us to make decisions in after_mediation callbacks based on changed state.
    def track_changes_for(ar_instance)
      changes << ar_instance
    end

    # True if we are currently in a nested mediated transaction call.
    def nested?
      stack.size > 1
    end

    def mediate(&block)
      debug("mediate called")
      stack.push(self)
      result = if idle?
        begin_transaction &block
      else
        debug("nested transaction; mediate yielding instead")
        yield self
      end
      debug("mediate finished successfully")
      return result

    ensure
      done! unless nested? # very important, so that calling methods can ensure cleanup
      stack.pop
    end

    [:debug, :info, :warn, :error, :fatal].each do |level|
      define_method(level) do |message| 
        mediated_instance.send("m_#{level}", "\e[4;32;1m#{self} - #{aasm_current_state} :\e[0m #{message}")
      end
    end

    # Reload the mediated instance.  Throws an ActiveRecord::StaleObjectError
    # if lock_column has been updated outside of transaction.
    def refresh_mediated_instance
      debug "refresh_mediated_instance called"
      unless mediated_instance.new_record?
        if mediated_instance.locking_enabled_without_mediation?
          locking_column = mediated_instance.class.locking_column
          current_lock_version = mediated_instance.send(locking_column) if locking_column
        end
        debug("reloading")
        mediated_instance.reload 
        raise(ActiveRecord::StaleObjectError) if current_lock_version && current_lock_version != mediated_instance.send(locking_column)
      end
    end

    private

    def begin_transaction(&block)
      debug("begin_transaction called")
      result = if mediation_enabled?
        start!
        _wrap_in_callbacks &block 
      else
        disable!
        debug("mediation disabled; begin_transaction yielding instead")
        yield self
      end
      debug("begin_transaction finished successfully")
      return result
    end

    def _wrap_in_callbacks
      debug("_wrap_in_callbacks called")
      debug("_wrap_in_callbacks before_mediation")
      mediated_instance.run_callbacks(:before_mediation)
      debug("_wrap_in_callbacks before_mediation completed")
      debug("_wrap_in_callbacks yielding")
      result = yield self
      # skip after_mediation if failed validation
      unless !result.nil? && result == false
        debug("_wrap_in_callbacks yielding completed")
        debug("_wrap_in_callbacks mediate_reconciles")
        mediated_instance.run_callbacks(:mediate_reconciles)
        refresh_mediated_instance # after having reconciled
        debug("_wrap_in_callbacks mediate_reconciles completed")
        debug("_wrap_in_callbacks mediate_caches")
        mediated_instance.run_callbacks(:mediate_caches)
        debug("_wrap_in_callbacks mediate_caches completed")
        debug("_wrap_in_callbacks bumping")
        bump!
        mediated_instance.touch if mediated_instance.class.locking_enabled?
        debug("_wrap_in_callbacks bumping done")
        refresh_mediated_instance # after having cached and versioned 
      end
      return result
    end
  end
end
