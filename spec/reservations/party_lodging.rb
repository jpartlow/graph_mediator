class PartyLodging < ActiveRecord::Base
  belongs_to :party, :counter_cache => true
  belongs_to :lodging, :counter_cache => true
end
