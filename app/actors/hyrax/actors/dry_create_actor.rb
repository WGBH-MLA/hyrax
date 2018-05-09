# frozen_string_literal: true
module Hyrax
  module Actors
    ##
    # An actor which short circuits the rest of the stack for `#create`,
    # replacing with a call to `Hyrax::Transactions::CreateWork`.
    class DryCreateActor < AbstractActor
      ##
      # @!attribute [rw] error_handler
      #   @return [#call]
      # @!attribute [rw] transaction
      #   @return [Dry::Transaction]
      attr_accessor :error_handler, :transaction

      ##
      # @param [Dry::Transaction] transaction
      def initialize(*args,
                     error_handler: ->(err) {},
                     transaction:   Hyrax::Transactions::CreateWork.new)
        self.error_handler = error_handler
        self.transaction   = transaction

        super(*args)
      end

      ##
      # Drops the remaining Actors in favor of the `CreateWork` transaction.
      def create(env)
        transaction
          .call(env.curation_concern)
          .or { |err| error_handler.call(err) && false }
      end
    end
  end
end
