require File.expand_path(File.join(File.dirname(__FILE__), 'spec_helper'))

describe "GraphMediator::Mediator" do

  it "should create a new activerecord object" do
    require 'reservations/schema'
    require 'reservations/reservation'
    Reservation.new(:name => 'John')
    Reservation.class_eval { include GraphMediator }
    Reservation.new(:name => 'John')
    Reservation.class_eval { mediate :when_reconciling => :foo }
    Reservation.new(:name => 'John')
    Reservation.class_eval do
      def initialize(*arguments)
        super
      end
    end
    Reservation.new(:name => 'John')
  end

end
