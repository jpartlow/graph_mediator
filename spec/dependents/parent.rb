module Dependents
  class Parent < ActiveRecord::Base
    include GraphMediator
    mediate :dependencies => Child

    has_many :children, :dependent => :destroy
  end

  # To test whether the order of declaration impacts function
  # For example, if we used before_destroy callbacks to mark a parent
  # as being destroyed, the order matters, because associations register
  # themselves for deletion when first declared using before_destroy as
  # well.
  class ReverseParent < ActiveRecord::Base
    has_many :reverse_children, :dependent => :destroy

    include GraphMediator
    mediate :dependencies => ReverseChild
  end
end
