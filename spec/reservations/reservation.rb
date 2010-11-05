require 'reservations/party'
require 'reservations/lodging'
require 'reservations/party_lodging'

class Reservation < ActiveRecord::Base
  has_many :parties
  has_many :lodgings
  has_many :party_lodgings, :through => :lodgings

  def lodge(party, options = {})
    lodging = options[:in]
    party.party_lodgings.create(:lodging_id => lodging)
  end
end
