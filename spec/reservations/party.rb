class Party < ActiveRecord::Base
  belongs_to :reservation, :counter_cache => true, touch: true
  has_many :party_lodgings
end
