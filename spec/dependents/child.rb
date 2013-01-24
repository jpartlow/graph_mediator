module Dependents
  class Child < ActiveRecord::Base
    belongs_to :parent
  end

  class ReverseChild < ActiveRecord::Base
    belongs_to :reverse_parent
  end
end
