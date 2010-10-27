require 'active_support/core_ext/class/inheritable_attributes'
require 'active_support/core_ext/module/attribute_accessors'
require 'active_support/core_ext/array/extract_options'
require 'active_support/callbacks'
require 'graph_mediator/mediator'

# = GraphMediator =
#
# GraphMediator is used to coordinate changes between a graph of ActiveRecord objects
# related to a root node.  See README.rdoc for details.
#
# GraphMediator::Base::DSL - is the simple class macro language used to set up mediation.
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
  
  # Enable or disable mediation globally.  Default: true
  mattr_accessor :enable_mediation
  self.enable_mediation = true

  CALLBACKS = [:before_mediation, :mediate_reconciles, :mediate_caches, :mediate_bumps]
 
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
      base.class_inheritable_accessor :__graph_mediator_version_column, :instance_writer => false
      base.class_inheritable_accessor :__graph_mediator_enabled, :instance_writer => false
      base.__send__(:_register_for_mediation, :save_without_transactions, :save_without_transactions!)
      base.__graph_mediator_enabled = true
    end

    # Inserts a new #{base}::MediatorProxy module with Proxy included.
    # All callbacks are defined in here for easy overriding in the Base
    # class.
    def _include_new_proxy(base)
      proxy = Module.new do
        include ActiveSupport::Callbacks
        include Proxy
      end
      base.const_set(:MediatorProxy, proxy)
      key = base.to_s.underscore.gsub('/','_').upcase
      hash_key = "GRAPH_MEDIATOR_#{key}_HASH_KEY"
      new_array_key = "GRAPH_MEDIATOR_#{key}_NEW_ARRAY_KEY"
      proxy.module_eval do
        define_method(:mediator_hash_key) do
          hash_key
        end
        protected(:mediator_hash_key)
        define_method(:mediator_new_array_key) do
          new_array_key
        end
        protected(:mediator_new_array_key)
      end
      base.send(:include, proxy)
      base.send(:extend, Proxy::ClassMethods)
      # Relies on ActiveSupport::Callbacks (which is included
      # into ActiveRecord::Base) for callback handling.
      base.define_callbacks *CALLBACKS
      return proxy 
    end

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
    end

    # Wraps the given block in a transaction and begins mediation. 
    def mediated_transaction(&block)
      mediator = _get_mediator
      mediator.mediate(&block)
    ensure
      if mediator && mediator.idle?
        mediators.delete(self.id)
        mediators_for_new_records.delete(mediator)
      end
    end
 
    # True if there is currently a mediated transaction begun for
    # this instance.
    def currently_mediating?
      mediators.include?(self.id)
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

    %w(destroy save save! toggle toggle! update_attribute update_attributes update_attributes!).each do |method|
      base, punctuation = parse_method_punctuation(method)
      define_method("#{base}_without_mediation#{punctuation}") do |*args,&block|
        disable_mediation!
        send(method) 
        enable_mediation!
      end
    end

    protected

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

    # Accessor the for the mediator associated with this instance's id, or nil if we are
    # not currently mediating.
    def current_mediator
      mediators[self.id]
    end 

    private

    def _get_mediator
      mediator = mediators[self.id] 
      mediator ||= mediators_for_new_records.find { |m| m.mediated_id == self.id }
      mediator ||= GraphMediator::Mediator.new(self)
      if new_record?
        mediators_for_new_records << (mediator = GraphMediator::Mediator.new(self))
      else
        mediators[self.id] = mediator
      end
      return mediator
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
  # The mediate() method takes options to set callbacks.  Or you can set them directly with
  # a method symbol, array of method symbols or a Proc.  They may be called multiple times
  # and may be added to in subclasses.
  #
  # * before_mediation - runs before mediation is begun
  # * - mediate and save
  # * mediate_reconciles - after saveing the instance, run any routines to make further 
  #   adjustments to the structure of the graph or non-cache attributes
  # * mediate_caches - routines for updating cache values
  # * mediate_bumps - increment the graph version
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
    include Util

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
    # You should not list methods used for reconcilation, cacheing or version
    # bumping.
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
    #   * :when_bumping => method or proc to execute to bump the overall graph version
    #   * :bumps => alternately, an attribute to increment (ignored if a mediate_bumps callback 
    #     is set)
    #
    # mediate :update_children,
    #   :dependencies => Child,
    #   :when_reconciling => :reconcile,
    #   :when_caching => :cache 
    #
    def mediate(*methods)
      options = methods.extract_options!
      when_bumping = options[:when_bumping]
      bumps = options[:bumps]
      raise(ArgumentError, "Set either :when_bumping or :bumps, but not both.") if when_bumping && bumps
    
      _register_for_mediation(*methods)
      mediate_reconciles(options[:when_reconciling]) if options[:when_reconciling]
      mediate_caches(options[:when_cacheing]) if options[:when_cacheing]
      mediate_bumps(options[:when_bumping]) if options[:when_bumping]
      self.__graph_mediator_version_column = bumps
    end

    private

    # Wraps each method in a mediated_transaction call.
    # The original method is aliased as :method_without_mediation so that it can be
    # overridden separately if needed.
    def _register_for_mediation(*methods)
      methods.each do |method|
        _alias_method_chain_ensuring_inheritability(method, :mediation) do |aliased_target,punctuation|
          __send__(:define_method, "#{aliased_target}_with_mediation#{punctuation}") do |*args, &block|
            mediated_transaction { __send__("#{aliased_target}_without_mediation#{punctuation}", *args, &block) }
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
end
