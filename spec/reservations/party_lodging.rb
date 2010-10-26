class PartyLodging < ActiveRecord::Base
  belongs_to :party
  belongs_to :lodging
end
