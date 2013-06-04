require 'cinch'
Dir.glob("plugins/*.rb").each {|x| require_relative x}
Dir.glob("plugins/*/*.rb").each {|x| require_relative x}

bot = Cinch::Bot.new do
  configure do |c|
    c.server = "irc.synirc.net"
    c.nick = "asterbot"
    c.channels = [ "#pad"]
    c.plugins.plugins = [Pazudora]
    c.plugins.options[Pazudora] = {
      :pddata => "db/pddata.yml"
    }
  end
end

bot.start
