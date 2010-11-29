require 'active_support'
require 'graph_mediator/mediator'
require 'graph_mediator/locking'
require 'graph_mediator/version'

# = GraphMediator =
#
# GraphMediator is used to coordinate changes between a graph of ActiveRecord objects
# related to a root node.  See README.rdoc for details.
#
# GraphMediator::Base::DSL - is the simple class macro language used to set up mediation.
#
# == Versioning and Optimistic Locking
#
# If you include an integer +lock_version+ column in your class, it will be incremented
# only once within a mediated_transaction and will serve as the optimistic locking check
# for the entire graph so long as you have declared all your dependent models for mediation.
#
# Outside of a mediated_transaction, +lock_version+ will increment per update as usual.
#
# == Convenience Methods for Save Without Mediation
#
# There are convenience method to perform a save, save!, toggle,
# toggle!, update_attribute, update_attributes or update_attributes!
# call without mediation.  They are of the form <method>_without_mediation<punc>
# 
# For example, save_without_mediation! is equivalent to:
#
# instance.disable_mediation!
# instance.save!
# instance.enable_mediation!
#
# == Overriding
# 
# GraphMediator overrides ActiveRecord's save_without_transaction to slip in mediation 
# just before the save process is wrapped in a transaction.
# 
# * save_without_transaction
# * save_without_transaction_with_mediation
# * save_without_transaction_without_mediation
# 
# may all be overridden in your implementation class, but they end up being
# defined locally by GraphMediator, so you can override with something like
# alias_method_chain, but will need to be in a subclass to use super.
# 
# My original intention was to define aliased overrides in MediatorProxy if the target
# was a method in a superclass (like save), so that the implementation class could
# make a simple def foo; something; super; end override, but this is prevented by a bug
# in ruby 1.8 with aliasing of methods that use super in a module.
# http://redmine.ruby-lang.org/issues/show/734
# 
module GraphMediator
  
  CALLBACKS = [:before_mediation, :mediate_reconciles, :mediate_caches, :mediate_bumps]
  SAVE_METHODS = [:save_without_transactions, :save_without_transactions!]
 
  # We want lib/graph_mediator to define GraphMediator constant
  require 'graph_mediator/mediator'

  class MediatorException < Exception; end

  # Methods used by GraphMediator to setup.
  class << self
    def included(base)
      base.class_eval do
        extend DSL
      end
      initialize_for_mediation(base)
    end
 
    private

    def initialize_for_mediation(base)
      _include_new_proxy(base)
      base.class_inheritable_accessor :__graph_mediator_enabled, :instance_writer => false
      base.__graph_mediator_enabled = true
      base.__send__(:class_inheritable_array, :graph_mediator_dependencies)
      base.graph_mediator_dependencies = []
      base.__send__(:_register_for_mediation, *(SAVE_METHODS.clone << { :track_changes => true }))
    end

    # Inserts a new #{base}::MediatorProxy module with Proxy included.
    # All callbacks are defined in here for easy overriding in the Base
    # class.
    def _include_new_proxy(base)
      # XXX How can _include_new_proxy be made cleaner or at least clearer?
      proxy = Module.new do
#        include ActiveSupport::Callbacks
        include Proxy
        mattr_accessor :_graph_mediator_logger
        mattr_accessor :_graph_mediator_log_level
      end
      base.const_set(:MediatorProxy, proxy)
      proxy._graph_mediator_logger = GraphMediator::Configuration.logger || base.logger
      proxy._graph_mediator_log_level = GraphMediator::Configuration.log_level

      base.send(:include, proxy)
      base.send(:extend, Proxy::ClassMethods)
      base.send(:include, Locking)

      key = base.to_s.underscore.gsub('/','_').upcase
      hash_key = "GRAPH_MEDIATOR_#{key}_HASH_KEY"
      new_array_key = "GRAPH_MEDIATOR_#{key}_NEW_ARRAY_KEY"
      eigen = base.instance_eval { class << self; self; end }
      eigen.class_eval do
        define_method(:mediator_hash_key) { hash_key }
        define_method(:mediator_new_array_key) { new_array_key }
      end

      # Relies on ActiveSupport::Callbacks (which is included
      # into ActiveRecord::Base) for callback handling.
      base.define_callbacks *CALLBACKS
      return proxy 
    end

  end

  module Configuration
    # Enable or disable mediation globally.  Default: true
    # TODO this doesn't effect anything yet
    mattr_accessor :enable_mediation
    self.enable_mediation = true

    # Global logger override for GraphMediator.  By default each class
    # including GraphMediator uses the class's ActiveRecord logger.  Setting
    # GraphMediator::Configuration.logger overrides this.
    mattr_accessor :logger
    
    # Log level may be adjusted just for GraphMediator globally, or for each class including
    # GraphMediator.  This should be an ActiveSupport::BufferedLogger log level constant
    # such as ActiveSupport::BufferedLogger::DEBUG
    mattr_accessor :log_level
    self.log_level = ActiveSupport::BufferedLogger::INFO
  end

  module Util
    # Returns an array of [<method>,<punctuation>] from a given method symbol.
    #
    # parse_method_punctuation(:save) => ['save',nil]
    # parse_method_punctuation(:save!) => ['save','!']
    def parse_method_punctuation(method)
      return method.to_s.sub(/([?!=])$/, ''), $1
    end
  end

  # All of the working methods for mediation, plus initial call backs.
  module Proxy
    extend Util
 
    module ClassMethods
      # Turn on mediation for all instances of this class. (On by default)
      def enable_all_mediation!
        self.__graph_mediator_enabled = true
      end

      # Turn off mediation for all instances of this class. (Off by default)
      #
      # This will cause new mediators to start up disabled, but existing 
      # mediators will finish normally.
      def disable_all_mediation!
        self.__graph_mediator_enabled = false
      end
    
      # True if mediation is enabled at the class level.
      def mediation_enabled?
        self.__graph_mediator_enabled
      end

      # True if we are currently mediating instances of any of the passed ids.
      def currently_mediating?(ids)
        Array(ids).detect do |id|
          mediators[id] || mediators_for_new_records.find { |m| m.mediated_id == id }
        end
      end

      # Unique key to access a thread local hash of mediators for specific
      # #{base}::MediatorProxy type.
      #
      # (This is overwritten by GraphMediator._include_new_proxy)
      def mediator_hash_key; end

      # Unique key to access a thread local array of mediators of new records for
      # specific #{base}::MediatorProxy type.
      #
      # (This is overwritten by GraphMediator._include_new_proxy)
      def mediator_new_array_key; end

      # The hash of Mediator instances active in this Thread for the Proxy's 
      # base class.
      #
      # instance.id => Mediator of (instance)
      #
      def mediators
        unless Thread.current[mediator_hash_key]
          Thread.current[mediator_hash_key] = {}
        end
        Thread.current[mediator_hash_key]
      end

      # An array of Mediator instances mediating new records in this Thread for
      # the Proxy's base class.
      def mediators_for_new_records
        unless Thread.current[mediator_new_array_key]
          Thread.current[mediator_new_array_key] = []
        end
        Thread.current[mediator_new_array_key]
      end

    end

    # Wraps the given block in a transaction and begins mediation. 
    def mediated_transaction(&block)
      m_debug("#{self}.mediated_transaction called")
      mediator = _get_mediator
      result = mediator.mediate(&block)
      m_debug("#{self}.mediated_transaction completed successfully")
      return result
    ensure
      if mediator && mediator.idle?
        mediators.delete(self.id)
        mediators_for_new_records.delete(mediator)
      end
    end
 
    # True if there is currently a mediated transaction begun for
    # this instance.
    def currently_mediating?
      !current_mediator.nil?
    end

    # Returns the state of the current_mediator or nil.
    def current_mediation_phase
      current_mediator.try(:aasm_current_state)
    end

    # Returns the hash of changes to the graph being tracked by the current
    # mediator or nil if not currently mediating.
    def mediated_changes
      current_mediator.try(:changes)
    end

    # Turn off mediation for this instance.  If currently mediating, it
    # will finish normally, but new mediators will start disabled.
    def disable_mediation!
      @graph_mediator_mediation_disabled = true
    end

    # Turn on mediation for this instance (on by default).
    def enable_mediation!
      @graph_mediator_mediation_disabled = false
    end

    # By default, every instance will be mediated and this will return true.
    # You can turn mediation on or off on an instance by instance basis with
    # calls to disable_mediation! or enable_mediation!.
    #
    # Mediation may also be disabled at the class level, but enabling or 
    # disabling an instance supercedes this.
    def mediation_enabled?
      enabled = @graph_mediator_mediation_disabled.nil? ?
        self.class.mediation_enabled? :
        !@graph_mediator_mediation_disabled
    end

    %w(save save! touch toggle toggle! update_attribute update_attributes update_attributes!).each do |method|
      base, punctuation = parse_method_punctuation(method)
      define_method("#{base}_without_mediation#{punctuation}") do |*args,&block|
        disable_mediation!
        send(method, *args, &block) 
        enable_mediation!
      end
    end

    [:debug, :info, :warn, :error, :fatal].each do |level|
      const = ActiveSupport::BufferedLogger.const_get(level.to_s.upcase)
      define_method("m_#{level}") do |message|
        _graph_mediator_logger.send(level, message) if _graph_mediator_log_level <= const
      end
    end

    protected

    def mediators
      self.class.mediators
    end
  
    def mediators_for_new_records
      self.class.mediators_for_new_records
    end

    # Accessor for the mediator associated with this instance's id, or nil if we are
    # not currently mediating.
    def current_mediator
      m_debug("#{self}.current_mediator called")
      mediator = mediators[self.id]
      mediator ||= mediators_for_new_records.find { |m| m.mediated_instance.equal?(self) || m.mediated_id == self.id }
      m_debug("#{self}.current_mediator found #{mediator || 'nothing'}")
      return mediator
    end 

    private

    # Gets the current mediator or initializes a new one.
    def _get_mediator
      m_debug("#{self}._get_mediator called")
      m_debug("#{self}.get_mediator in a new record") if new_record?
      unless mediator = current_mediator
        mediator = GraphMediator::Mediator.new(self)
        m_debug("#{self}.get_mediator created new mediator")
        new_record? ?
          mediators_for_new_records << mediator :
          mediators[self.id] = mediator
      end
      m_debug("#{self}._get_mediator obtained #{mediator}")
      return mediator
    end

  end

  module AliasExtension #:nodoc:
    include Util

    private

    # Wraps each method in a mediated_transaction call.
    # The original method is aliased as :method_without_mediation so that it can be
    # overridden separately if needed.
    #
    # * options:
    #   * :through => root node accessor that will be the target of the
    #   mediated_transaction.  By default self is assumed.
    #   * :track_changes => if true, the mediator will track changes such
    #   that they can be reviewed after_mediation.  The after_mediation
    #   callbacks occur after dirty has completed and changes are normally lost.
    #   False by default.  Normally only applied to save and destroy methods.
    def _register_for_mediation(*methods)
      options = methods.extract_options!
      root_node_accessor = options[:through]
      track_changes = options[:track_changes]
      methods.each do |method|
        saveing = method.to_s =~ /save/
        destroying = method.to_s =~ /destroy/
        _alias_method_chain_ensuring_inheritability(method, :mediation) do |aliased_target,punctuation|
          __send__(:define_method, "#{aliased_target}_with_mediation#{punctuation}") do |*args, &block|
            root_node = (root_node_accessor ? send(root_node_accessor) : self)
            unless root_node.nil?
              root_node.mediated_transaction do |mediator|
                mediator.debug("#{root_node} mediating #{aliased_target}#{punctuation} for #{self}")
                mediator.track_changes_for(self) if track_changes && saveing
                result = __send__("#{aliased_target}_without_mediation#{punctuation}", *args, &block)
                mediator.track_changes_for(self) if track_changes && destroying
                mediator.debug("#{root_node} done mediating #{aliased_target}#{punctuation} for #{self}")
                result
              end
            else
              __send__("#{aliased_target}_without_mediation#{punctuation}", *args, &block)
            end
          end
        end
      end
    end

    def _method_defined(method, anywhere = true)
      (instance_methods(anywhere) + private_instance_methods(anywhere)).include?(RUBY_VERSION < '1.9' ? method.to_s : method)
    end

    # This uses Tammo Freese's patch to alias_method_chain.
    # https://rails.lighthouseapp.com/projects/8994/tickets/285-alias_method_chain-limits-extensibility
    #
    # target, target_with_mediation, target_without_mediation should all be
    # available for decorating (via aliasing) in the base class including the
    # MediatorProxy, as well as in it's subclasses (via aliasing or direct
    # overriding).  Overrides made higher up the chain should flow through as
    # well
    #
    # If the target has not been defined yet, there's nothing we can do, and we
    # raise a MediatorException
    def _alias_method_chain_ensuring_inheritability(target, feature, &block)
      raise(MediatorException, "Method #{target} has not been defined yet.") unless _method_defined(target)
 
      # Strip out punctuation on predicates or bang methods since
      # e.g. target?_without_feature is not a valid method name.
      aliased_target, punctuation = parse_method_punctuation(target)
      with_method, without_method = "#{aliased_target}_with_#{feature}#{punctuation}", "#{aliased_target}_without_#{feature}#{punctuation}"

      method_defined_here = _method_defined(target, false)
      unless method_defined_here
        module_eval do
          define_method(target) do |*args, &block|
            super
          end
        end 
      end  
      
      __send__(:alias_method, without_method, target)
    
      if block_given?
        # create with_method
        yield(aliased_target, punctuation)
      end
  
      target_method_exists = _method_defined(with_method)
      raise NameError unless target_method_exists
      
      module_eval do
        define_method(target) do |*args, &block|
          __send__(with_method, *args, &block)
        end
      end
    end
 
  end 

  # DSL for setting up and describing mediation.
  #
  # save and save! are automatically wrapped for mediation when GraphMediator
  # is included into your class.  You can mediate other methods with a call to
  # mediate(), and can setup callbacks for reconcilation, cacheing or version
  # bumping.
  #
  # = Callbacks
  #
  # The mediate() method takes options to set callbacks.  Or you can set them
  # directly with a method symbol, array of method symbols or a Proc.  They may
  # be called multiple times and may be added to in subclasses.
  #
  # * before_mediation - runs before mediation is begun
  # * - mediate and save
  # * mediate_reconciles - after saveing the instance, run any routines to make further 
  #   adjustments to the structure of the graph or non-cache attributes
  # * mediate_caches - routines for updating cache values
  #
  # Example: 
  #
  # mediate_reconciles :bar do |instance|
  #   instance.something_else
  # end
  # mediate_reconciles :baz
  #
  # will ensure that [:bar, <block>, :baz] are run in 
  # sequence after :foo is done saveing within the context of a mediated
  # transaction.
  #
  module DSL
    include AliasExtension

    # Establishes callbacks, dependencies and possible methods as entry points 
    # for mediation.
    #
    # * :methods => list of methods to mediate (automatically wrap in a
    # mediated_transaction call)
    #
    # ActiveRecord::Base.save is decorated for mediation when GraphMediator
    # is included into your model.  If you have additional methods which 
    # perform bulk operations on members, you probably want to list them
    # here so that they are mediated as well.
    #
    # You should not list methods used for reconcilation, or cacheing.
    #
    # This macro takes a number of options:
    # 
    # * :options => hash of options
    #   * :dependencies => list of dependent member classes whose save methods
    #     should be decorated for mediation as well.
    #   * :when_reconciling => list of methods to execute during the after_mediation 
    #     reconcilation phase
    #   * :when_cacheing => list of methods to execute during the after_mediation 
    #     cacheing phase
    #
    # mediate :update_children,
    #   :dependencies => Child,
    #   :when_reconciling => :reconcile,
    #   :when_caching => :cache 
    #
    # = Dependent Classes
    #
    # Dependent classes have their save methods mediated as well.  However, a
    # dependent class must provide an accessor for the root node, so that a
    # mediated_transaction can be begun in the root node when a dependent is
    # changed.
    #
    # = Versioning and Optimistic Locking
    #
    # GraphMediator uses the class's lock_column (default +lock_version+) and
    # +updated_at+ or +updated_on+ for versioning and locks checks during
    # mediation.  The lock_column is incremented only once during a mediated_transaction.
    # 
    # +Unless both these columns are present in the schema, versioning/locking
    # will not happen.+  A lock_column by itself will not be updated unless
    # there is an updated_at/on timestamp available to touch.
    # 
    def mediate(*methods)
      options = methods.extract_options!
      self.graph_mediator_dependencies = Array(options[:dependencies] || [])
 
      _register_for_mediation(*methods)
      graph_mediator_dependencies.each do |dependent_class|
        dependent_class.send(:extend, AliasExtension) unless dependent_class.include?(AliasExtension)
        methods = SAVE_METHODS.clone
        methods << :destroy
        methods << { :through => self.class_of_active_record_descendant(self).to_s.demodulize.underscore, :track_changes => true }
        dependent_class.send(:_register_for_mediation, *methods)
      end
      mediate_reconciles(options[:when_reconciling]) if options[:when_reconciling]
      mediate_caches(options[:when_cacheing]) if options[:when_cacheing]
    end

  end
end
