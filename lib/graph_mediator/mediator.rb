require 'aasm'

module GraphMediator
  # Instances of this class perform the actual mediation work on behalf of a
  # Proxy#mediated_transaction.
  class Mediator
    include AASM

    # An instance of the root ActiveRecord object currently under mediation.
    attr_accessor :mediated_instance

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
      transitions :from => [:mediating, :versioning, :disabled], :to => :idle
    end

    def initialize(instance)
      raise(ArgumentError, "Given instance has not been initialized for mediation: #{instance}") unless instance.kind_of?(GraphMediator)
      self.mediated_instance = instance
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

    def mediate(&block)
      result = if idle?
        begin_transaction &block
      else
        yield
      end
      return result
    rescue SystemStackError => e
      # out of control recursion, probably from trying to touch a new record in a before_create?
      raise(GraphMediator::MediatorException, "SystemStackError (#{e}).  Is there an attempt to call a mediated_transaction in a before_create callback?")
    end

    private

    def begin_transaction(&block)
      result = if mediation_enabled?
        start!
        _wrap_in_callbacks &block 
      else
        disable!
        yield
      end
      done!
      return result
    end

    def _wrap_in_callbacks
      mediated_instance.run_callbacks(:before_mediation)
      result = yield
      mediated_instance.run_callbacks(:mediate_reconciles)
      mediated_instance.run_callbacks(:mediate_caches)
      bump!
      mediated_instance.touch if mediated_instance.class.locking_enabled?
      # TODO work out bump column
      return result
    end
  end
end
