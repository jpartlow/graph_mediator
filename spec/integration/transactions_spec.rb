require File.expand_path(File.join(File.dirname(__FILE__), '..', 'spec_helper'))

require 'reservations/party_lodging'
require 'reservations/lodging'
require 'reservations/party'
require 'reservations/reservation'

describe "GraphMediator transaction scenarios" do

  before(:all) do
    load 'reservations/schema.rb'
  end

  before(:each) do
    @today = Date.today
    @r1 = Reservation.create!(:starts => @today, :ends => @today + 1, :name => 'foo')
  end

  it "should implicitly provide an activerecord transaction for mediated_transaction" do
    lambda {
      @r1.mediated_transaction do
        @r1.parties.create(:name => 'Bob')
        raise('should cause transaction rollback')
      end
    }.should raise_error(RuntimeError)
    @r1.reload
    @r1.parties.should be_empty 
  end

  it "should handle rollback in a mediated_transaction" do
    @r1.mediated_transaction do
      @r1.parties.create(:name => 'Bob')
      raise(ActiveRecord::Rollback)
    end
    @r1.reload
    @r1.parties.should be_empty 
  end

end
