require_relative "mysql/connection"
require_relative "mysql/errors"
require_relative "mysql/views"
require_relative "mysql/tables_definition"
require_relative "mysql/version"

module Scenic
  # Scenic database adapters.
  #
  # Scenic ships with a Postgres adapter only but can be extended with
  # additional adapters. The {Adapters::Postgres} adapter provides the
  # interface.
  module Adapters
    # An adapter for managing MySQL views.
    #
    # These methods are used interally by Scenic and are not intended for direct
    # use. Methods that alter database schema are intended to be called via
    # {Statements}, while {#refresh_materialized_view} is called via
    # {Scenic.database}.
    #
    # The methods are documented here for insight into specifics of how Scenic
    # integrates with Postgres and the responsibilities of {Adapters}.
    class Mysql
      # Creates an instance of the Scenic Postgres adapter.
      #
      # This is the default adapter for Scenic. Configuring it via
      # {Scenic.configure} is not required, but the example below shows how one
      # would explicitly set it.
      #
      # @param [#connection] connectable An object that returns the connection
      #   for Scenic to use. Defaults to `ActiveRecord::Base`.
      #
      # @example
      #  Scenic.configure do |config|
      #    config.adapter = Scenic::Adapters::Postgres.new
      #  end
      def initialize(connectable = ActiveRecord::Base)
        @connectable = connectable
      end

      # Returns an array of views in the database.
      #
      # This collection of views is used by the [Scenic::SchemaDumper] to
      # populate the `schema.rb` file.
      #
      # @return [Array<Scenic::View>]
      def views
        Views.new(connection).all
      end

      # Creates a view in the database.
      #
      # This is typically called in a migration via {Statements#create_view}.
      #
      # @param name The name of the view to create
      # @param sql_definition The SQL schema for the view.
      #
      # @return [void]
      def create_view(name, sql_definition)
        execute "CREATE VIEW #{quote_table_name(name)} AS #{sql_definition};"
      end

      # Updates a view in the database.
      #
      # This results in a {#drop_view} followed by a {#create_view}. The
      # explicitness of that two step process is preferred to `CREATE OR
      # REPLACE VIEW` because the former ensures that the view you are trying to
      # update did, in fact, already exist. Additionally, `CREATE OR REPLACE
      # VIEW` is allowed only to add new columns to the end of an existing
      # view schema. Existing columns cannot be re-ordered, removed, or have
      # their types changed. Drop and create overcomes this limitation as well.
      #
      # This is typically called in a migration via {Statements#update_view}.
      #
      # @param name The name of the view to update
      # @param sql_definition The SQL schema for the updated view.
      #
      # @return [void]
      def update_view(name, sql_definition)
        drop_view(name)
        create_view(name, sql_definition)
      end

      # Drops the named view from the database
      #
      # This is typically called in a migration via {Statements#drop_view}.
      #
      # @param name The name of the view to drop
      #
      # @return [void]
      def drop_view(name)
        execute "DROP VIEW #{quote_table_name(name)};"
      end

      # Creates a materialized view in the database
      #
      # @param name The name of the materialized view to create
      # @param sql_definition The SQL schema that defines the materialized view.
      #
      # This is typically called in a migration via {Statements#create_view}.
      #
      # @raise [MaterializedViewsNotSupportedError] if the version of Postgres
      #   in use does not support materialized views.
      #
      # @return [void]
      def create_materialized_view(name, sql_definition)
        raise_unless_materialized_views_supported
      end

      # Updates a materialized view in the database.
      #
      # Drops and recreates the materialized view. Attempts to maintain all
      # previously existing and still applicable indexes on the materialized
      # view after the view is recreated.
      #
      # This is typically called in a migration via {Statements#update_view}.
      #
      # @param name The name of the view to update
      # @param sql_definition The SQL schema for the updated view.
      #
      # @raise [MaterializedViewsNotSupportedError] if the version of Postgres
      #   in use does not support materialized views.
      #
      # @return [void]
      def update_materialized_view(name, sql_definition)
        raise_unless_materialized_views_supported
      end

      # Drops a materialized view in the database
      #
      # This is typically called in a migration via {Statements#update_view}.
      #
      # @param name The name of the materialized view to drop.
      # @raise [MaterializedViewsNotSupportedError] if the version of Postgres
      #   in use does not support materialized views.
      #
      # @return [void]
      def drop_materialized_view(name)
        raise_unless_materialized_views_supported
      end

      # Refreshes a materialized view from its SQL schema.
      #
      # This is typically called from application code via {Scenic.database}.
      #
      # @param name The name of the materialized view to refresh.
      # @param concurrently [Boolean] Whether the refreshs hould happen
      #   concurrently or not. A concurrent refresh allows the view to be
      #   refreshed without locking the view for select but requires that the
      #   table have at least one unique index that covers all rows. Attempts to
      #   refresh concurrently without a unique index will raise a descriptive
      #   error.
      #
      # @raise [MaterializedViewsNotSupportedError] if the version of Postgres
      #   in use does not support materialized views.
      # @raise [ConcurrentRefreshesNotSupportedError] when attempting a
      #   concurrent refresh on version of Postgres that does not support
      #   concurrent materialized view refreshes.
      #
      # @example Non-concurrent refresh
      #   Scenic.database.refresh_materialized_view(:search_results)
      # @example Concurrent refresh
      #   Scenic.database.refresh_materialized_view(:posts, concurrent: true)
      #
      # @return [void]
      def refresh_materialized_view(name, concurrently: false)
        raise_unless_materialized_views_supported
      end

      private

      attr_reader :connectable
      delegate :execute, :quote_table_name, to: :connection

      def connection
        Connection.new(connectable.connection)
      end

      def raise_unless_materialized_views_supported
        unless connection.supports_materialized_views?
          raise MaterializedViewsNotSupportedError
        end
      end

      def raise_unless_concurrent_refresh_supported
        unless connection.supports_concurrent_refreshes?
          raise ConcurrentRefreshesNotSupportedError
        end
      end
    end
  end
end
