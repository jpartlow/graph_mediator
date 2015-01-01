class Reservation < ActiveRecord::Base
  has_many :parties
  has_many :lodgings
  has_many :party_lodgings, :through => :lodgings

  include GraphMediator
  mediate :dependencies => [Lodging, Party], 
    :when_reconciling => :reconcile,
    :when_cacheing => :cache

  def lodge(party, options = {})
    lodging = options[:in]
    party.party_lodgings.create!(:lodging => lodging)
  end

  def reconcile; :reconcile; end
  def cache; :cache; end
end
