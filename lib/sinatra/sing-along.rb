require "sinatra/base"
require "fiber"
require "rack/fiber_pool"
require "json"

module Sinatra
  module SingAlong
    
    module Helpers
      def broadcast(message_type, data)
        message = { 
          :message_type => message_type, 
          :message_data => data, 
          :timestamp => Time.new }
        
        (@@queue ||= []) << message
        
        send_message message
      end
    end
    
    def on(message_type, &block)
      (@@handlers ||= {})[message_type] = block if block_given?
    end

    def self.registered(app)
      app.use Rack::FiberPool
      app.helpers SingAlong::Helpers
      
      app.post "/sing-along/xhr/poll" do
        request.body.rewind
        data = JSON.parse request.body.read
        last_timestamp = data["last_timestamp"]
        context = data["context"]
        messages = get_messages(last_timestamp)
        
        if messages.length == 0
          fiber = Fiber.current
          (@@callbacks ||= []) << { :timestamp => Time.new, :callback => Proc.new { |messages|
            fiber.resume(messages)
          }}
          messages = Fiber.yield
        end
        
        puts "sending messages"
        
        return { 
          :context => context,
          :messages => messages }.to_json
      end
      
      app.post "/sing-along/xhr/send" do
        request.body.rewind
        data = JSON.parse request.body.read
        message_type, message_data, context = data["message_type"].to_sym, data["message_data"], data["context"]
        handler = (@@handlers ||= {})[message_type]
        return if handler.nil?
        
        instance_exec(message_data, context, &handler)
        
        return {
          :context => context
        }.to_json
      end
      
      app.get "/jquery.sing-along.js" do
        path = File.dirname(__FILE__)
        file = File.join(path, "/sing-along/jquery.sing-along.js")
        send_file(file)
      end
      
      # add clean-up timer
    end
    
    def get_messages(from)
      messages = []
      queue = (@@queue ||= [])
      return nil if queue.nil?
      queue.each { |message| messages << message if message[:timestamp] > from }
      messages
    end
    
    def send_message(message)
      while (@@callbacks ||= []).length > 0
        @@callbacks.shift[:callback].call([message])
      end
    end
    
  end
  
  register SingAlong
end