require 'reservations/party'
require 'reservations/lodging'
require 'reservations/party_lodging'

class Reservation < ActiveRecord::Base
  has_many :parties
  has_many :lodgings
  has_many :party_lodgings, :through => :lodgings
end
