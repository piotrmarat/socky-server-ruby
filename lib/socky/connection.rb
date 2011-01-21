require 'json'
require 'socky/connection/authentication'
require 'socky/connection/finders'

module Socky
  # every connection to server creates one instance of Connection
  class Connection
    include Socky::Misc
    include Socky::Connection::Authentication
    extend Socky::Connection::Finders

    # reference to connection socket
    attr_reader :socket

    class << self
      # list of all connections in pool
      # @return [Array] list of connections
      def connections
        @connections ||= []
      end
    end

    # initialize new connection
    # @param [WebSocket] socket valid connection socket
    def initialize(socket)
      @socket = socket
    end

    # read query data from socket request
    # @return [Hash] hash of query data
    def query
      socket.request["Query"] || {}
    end

    # return if user appear to be admin
    # this one should not be base to imply that user actually is
    # admin - later authentication is needed
    # @return [Boolean] is user claim to be admin?
    def admin
      ["true","1"].include?(query["admin"])
    end

    # user individual id - multiple connection can be organized
    # by user id and later accessed at once
    # @return [String] user id(might be nil)
    def user
      query["user_id"]
    end

    # user individual secret - used to check if user is admin
    # and to sending authentication data to server(by subscribe_url)
    # @return [String] user secret(might be nil)
    def secret
      query["user_secret"]
    end

    # user channel list - one user can have multiple channels
    # every user have at last channel - if no channels are provided
    # at default then user is assigned to nil channel
    # @return [Array] list of user channels
    def channels
      @channels ||= query["channels"].to_s.split(",").collect(&:strip).reject(&:empty?)
      @channels[0] ||= nil # Every user should have at last one channel
      @channels
    end

    # check if user is valid and add him to pool or disconnect
    def subscribe
      debug [self.name, "incoming"]
      subscribe_request
    end

    # remove user from pool and disconnect
    def unsubscribe
      debug [self.name, "terminated"]
      unsubscribe_request
    end

    # check if user can send messages and process it
    # @see Socky::Message.process
    # @param [String] msg message to send in json format
    def process_message(msg)
      if admin && authenticated?
        Socky::Message.process(self, msg)
      else
        self.send_message "You are not authorized to post messages"
      end
    end

    # send message to user
    # @param [Object] msg data to send(will be converted to json using to_json method)
    def send_message(msg)
      send_data({:type => :message, :body => msg})
    end

    # disconnect connection
    def disconnect
      socket.close_connection_after_writing
    end

    # convert connection to json(used in show_connection query)
    # @param [Any] args it is required by different versions of ruby
    # @return [JSon] id, user_id and channel list data
    def to_json(*args)
      {
        :id => self.object_id,
        :user_id => self.user,
        :channels => self.channels.reject{|channel| channel.nil?}
      }.to_json
    end

    private

    def send_data(data)
      json_data = data.to_json
      debug [self.name, "sending data", json_data]
      socket.send json_data
    end

    def connection_pool
      self.class.connections
    end

    def in_connection_pool?
      connection_pool.include?(self)
    end

    def add_to_pool
      connection_pool << self unless self.admin || in_connection_pool?
    end

    def remove_from_pool
      connection_pool.delete(self)
    end

  end
end