module GraphMediator
  # Overrides to ActiveRecord::Optimistic::Locking to ensure that lock_column is updated
  # during the +versioning+ phase of a mediated transaction.
  module Locking

    def self.included(base)
      base.extend(ClassMethods)
      base.send(:alias_method, :locking_enabled_without_mediation?, :locking_enabled?)
      base.send(:include, InstanceMethods)
    end

    module ClassMethods
      # Overrides ActiveRecord::Base.update_counters to skip locking if currently mediating
      # the passed id.
      def update_counters(ids, counters)
        # id may be an array of ids...
        unless currently_mediating?(ids)
          # if none are being mediated can proceed as normal
          super
        else
          # we have to go one by one unfortunately
          Array(ids).each do |id|
            currently_mediating?(id) ?
              update_counters_without_lock(id, counters) :
              super
          end
        end
      end
    end

    module InstanceMethods
      # Overrides ActiveRecord::Locking::Optimistic#locking_enabled?
      #
      # * True if we are not in a mediated_transaction and lock_enabled? is true
      # per ActiveRecord (lock_column exists and lock_optimistically? true)
      # * True if we are in a mediated_transaction and lock_enabled? is true per
      # ActiveRecord and we are in the midst of the version bumping phase of the transaction.
      # 
      # Effectively this ensures that an optimistic lock check and version bump
      # occurs as usual outside of mediation but only at the end of the
      # transaction within mediation.
      def locking_enabled?
        locking_enabled = locking_enabled_without_mediation?
        locking_enabled &&= current_mediation_phase == :versioning if mediation_enabled? && currently_mediating?
        return locking_enabled
      end
    end

  end
end
