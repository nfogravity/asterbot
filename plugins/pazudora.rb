require 'cinch'
require 'nokogiri'
require 'pry'
require 'open-uri'
require 'calc'
require 'distribution'
require 'gist'
require 'yaml'
require 'bitly'

class Pazudora
  include Cinch::Plugin

  PUZZLEMON_BASE_URL = "http://www.puzzledragonx.com/en/"
  GACHA_URL = "http://www.puzzledragonx.com/egg.asp"
  RANK_TABLE_URL = "http://www.puzzledragonx.com/en/levelchart.asp"

  match /pazudora ([\w-]+) *(.+)*/i, method: :pazudora
  match /stupidpuzzledragonbullshit ([\w-]+) *(.+)*/i, method: :pazudora
  match /stupiddragonpuzzlebullshit ([\w-]+) *(.+)*/i, method: :pazudora
  match /p&d ([\w-]+) *(.+)*/i, method: :pazudora
  match /pad ([\w-]+) *(.+)*/i, method: :pazudora
  match /puzzlemon ([\w-]+) *(.+)*/i, method: :pazudora
  match /puzzledex (.+)*/i, method: :pazudora_lookup

  @help_string = <<-eos
  Puzzle and Dragons (on iOS and Android) utility functions. Mostly collects friend codes and tracks the daily dungeon.
  Its commands are aliased to pazudora, p&d, pad, and puzzlemon.
  eos
  @help_hash = {
      :add => "Usage: !puzzlemon add NAME CODE
Example: !puzzlemon add steggybot 123,456,789
Adds user's code to the list of friend codes",
      :group => "Usage: !puzzlemon group NAME
Example !puzzlemon group steggybot
Returns the daily dungeon group that the user belongs to.",
      :dailies => "Usage: !puzzlemon dailies
Example !puzzlemon dailies
Returns the times (and type) of today's daily dungeons, split by group. If called by
a registered player, also reminds them of their group id. Buggy.",
      :lookup => "Usage: !(puzzlemon lookup|puzzledex) (NAME|ID)
Example !puzzlemon lookup horus, !puzzledex 603
Returns a description of the puzzlemon. Aliases: dex",
      :list => "Usage: !puzzlemon list
Example !puzzlemon list
Returns a list of everyone's friends codes.",
      :chain => "Usage: !puzzlemon chain (NAME|ID)
Example !puzzlemon chain siren
Returns a sumary of the given puzzlemon's evolutionary family.",
      :evolution => "Usage: !puzzlemon evolution
Example !puzzlemon evolution siren
Returns the set of evo materials necessary to advance to the next tier. Aliases: materials, mats, evolve",
      :experience => "Usage: !puzzlemon experience [FROM]
Example !puzzlemon siren 24
Calculates the amount of experience required to max out this puzzlemon. From defaults to 1.
Aliases: exp, level. YES I KNOW THERE ARE NO LIGHT/DARK PENGDRAS A BLOOO BOO HOO",
      :rank => "Usage: !puzzlemon rank (RANK|TO FROM)
Example !puzzlemon rank 60, !puzzlemon rank 100 120
Returns information about a given player rank, or calculates the deltas between them.
Reverse lookup also possible: !puzzlemon rank stamina 100 computes when you will get 100 stamina.",
      :gacha => "Usage: !puzzlemon gacha
Simulates (poorly) a pull from the rare egg machine. Supports godfest modifiders--use !pad gacha tags for more information.
User !puzzlemon gacha MONSTER to learn how many rolls you'll need to get that monster, e.g !pad gacha Horus
Are you feeling lucky? This command can change that. Aliases: pull, roll",
      :stamina => "Usage: !puzzlemon stamina START END TIMEZONE
Computes how long it will take to go from START (default 0) to END stamina, and when it will happen in your timezone.
Input your timezone as an integer UTC offset, e.g +7 or -11. Defaults to -7 (pacific daylight savings).",
      :time => "Usage: !puzzlemon time STAMINA TIME TIMEZONE
Computes how much stamina you will have at TIME, assuming you have STAMINA stamina right now (default 0).
Input your timezone as an integer UTC offset, e.g +7 or -11. Defaults to -7 (pacific daylight savings).",
      :calc => "Usage: !puzzlemon calc expr
Computes an arbitrary mathematical expression in ruby. It's sanitized so don't try and funny shit. USE FLOATING POINTS.
Example: !pad calc 0.8 ** 5 for your odds of getting screwed on a 5 skillup feed.",
      :skillup => "Usage: !puzzlemon skillup K, N, p?
Computes the probability of getting K or more skillups in N feeds, assuming a skillup probability p (default 0.2).
Backed by somebody else's cdf function; if you get a crpytic domain error you've typed something in wrong. Probably.
Aliases: skill, cdf, bino, binomial"
  }

  HELP = @help_hash

  ALIAS = {
      "code" => "who",
      "fc" => "who",
      "delete" => "remove",
      "dex" => "lookup",
      "info" => "lookup",
      "evolve" => "evolution",
      "materials" => "evolution",
      "evo" => "evolution",
      "mats" => "evolution",
      "xp" => "experience",
      "exp" => "experience",
      "level" => "experience",
      "pull" => "gacha",
      "roll" => "gacha",
      "stam" => "stamina",
      "math" => "calc",
      "skill" => "skillup",
      "cdf" => "binomial",
      "bino" => "binomial",
  }

  def initialize(*args)
    super
    @pddata = config[:pddata]
    @alarms = []
    @clock = nil
  end

  #Any public method named pazudora_[something] is external and
  #can be accessed by the user using the construction "!puzzlemon something [args]".
  def pazudora (m, cmd, args)
    subr = cmd.downcase.chomp
    subr = ALIAS[subr] || subr
    begin
      if args
        self.send("pazudora_#{subr}", m, args)
      else
        self.send("pazudora_#{subr}", m, "")
      end
    rescue NoMethodError
      puts "Pazudora called with invalid command #{subr}."
      raise
    end
  end

  def pazudora_annoy_someone(m, args)
    return unless m.user.nick.include?("Asterism") 
    target = args
    m.reply "#{rand}"
    loop do
      delay = rand(3600)
      sleep(delay)
      m.reply "#{target} rubber boogie baby bumpers"    
    end
  end

  def pazudora_help(m, args)
    if args == ""
      r = "Usage: !pad help COMMAND.\n"
      r += "Registered commands are: #{HELP.keys.join(', ')}"
      m.reply r
    else
      helpstr = HELP[args.to_sym]
      m.reply "Unknown subcommand #{args}" and return unless helpstr
      m.reply helpstr
    end
  end

  def pazudora_clockup(m, args)
    #laffo
    return unless m.user.nick.include?("Asterism") 
    if @clock
      m.reply "Run only one clock, you moron."
      return
    end
    m.reply "Spinning up clock process at #{Time.now}"

    dailies = enqueue_dailies(m.channel.name)
    m.reply "Auto-enqueued #{dailies} daily dungeons successfully." 

    @clock = true
    today = Time.now.day
    while true
      sleep 10
      reap = []
      @alarms.each do |alarm|
        delta = Time.now - alarm[:time]
        next unless delta > 0 && delta < 60
        reap << alarm
        alarm_message = "#{alarm[:user]}: alarm #{alarm[:text]} has fired!"
        Channel(alarm[:channel]).send(alarm_message)
      end
      @alarms = @alarms.delete_if {|alarm| reap.include?(alarm)}

      if Time.now.hour == 0 && Time.now.day != today
        @alarms.delete_if {|alarm| alarm[:text] == "Hourly dungeon"}
        dailies = enqueue_dailies(m.channel.name)
        m.reply "It's after midnight--auto-enqueued #{dailies} daily dungeons again."
        today = Time.now.day
      end
    end
  end

  def pazudora_alarm(m, args)
    if m.channel.nil?
      m.reply "For Reasons(TM), asterbot does not allow alarm activation over PM."
      return
    end

    argv = args.split(" ")
    if argv.last.match(/(\+|\-)\d+/)
      timezone = argv.pop
      offset = timezone.to_i
      offset = offset * -1 if offset < 0
      if offset > 0 && offset < 10
        offset = "0#{offset}"
      elsif offset >= 24
        m.reply "Invalid UTC offset #{offset}" and return
      else
        offset = offset.to_s
      end
      utc = "#{timezone[0,1]}#{offset}:00"
    else
      utc = "-07:00"
    end

    given_time = argv.last
    text = (argv.length == 1) ? "(generic)" : argv[0..-2].join(" ")
    target_time = DateTime.strptime(given_time + utc, "%H:%M%z").to_time
    @alarms << {:time => target_time, :text => text, :channel => m.channel.name, :user => m.user.nick}
    m.reply "Alarm set for " + target_time.strftime("%I:%M%p UTC") + utc
    p @alarms
  end

  def pazudora_calc(m, args)
    output = Calc.evaluate(args.gsub(/\^/, "**"))
    if output.respond_to?(:round)
      if output.to_s.include?(".")
        m.reply "#{args} = %.3f" % output
      else
        m.reply "#{args} = #{output}"
      end
    else
      m.reply "Could not interpret #{args} as a mathematical expression"
    end
  end

  def pazudora_skillup(m, args)
    argv = args.split(" ")
    if argv.length == 3
      k = argv[0].to_i
      n = argv[1].to_i
      p = argv[2].to_f
    elsif argv.length == 2
      k = argv[0].to_i
      n = argv[1].to_i
      p = 0.2
    else
      m.reply ("USAGE: !pad skillup K N p") and return
    end

    if k == 0
      m.reply ("Your odds of getting 0 or more skillups is 1, doofus.") and return
    end

    begin
      screwed = Distribution::Binomial::cdf(k-1, n, p)
      ok = (1.0 - screwed).round(3)
      m.reply("On #{n} feeds (p=#{p}), your odds of getting #{k} or more skillups is #{ok}.")
    rescue ArgumentError => e
      m.reply("Bad query: #{e.message}") 
    end 
  end

  #kill me
  def pazudora_binomial(m, args)
    argv = args.split(" ")
    if argv.length == 3
      k = argv[0].to_i
      n = argv[1].to_i
      p = argv[2].to_f
    elsif argv.length == 2
      k = argv[0].to_i
      n = argv[1].to_i
      p = 0.2
    else
      m.reply ("USAGE: !pad skillup K N p") and return
    end

    if k == 0
      m.reply ("Your odds of getting 0 or more successes is 1, doofus.") and return
    end

    begin
      screwed = Distribution::Binomial::cdf(k-1, n, p)
      ok = (1.0 - screwed).round(3)
      m.reply("On #{n} trials (p=#{p}), your odds of getting #{k} or more successes is #{ok}.")
    rescue ArgumentError => e
      m.reply("Bad query: #{e.message}") 
    end 
  end

  def pazudora_add (m, args)
    pargs = args.split
    username = pargs[0]
    friend_code = pargs[1]

    # add it to the list
    friend_codes = load_data || {}
    if friend_code =~ /[0-9]{9}/
      friend_code = friend_code.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
    end
    if friend_codes[username.downcase] && (friend_codes[username.downcase][:added_by] == username.downcase)
      if m.user.nick.downcase == username.downcase
        friend_codes[username.downcase] = {:friend_code => friend_code, :added_by => m.user.nick.downcase, :updated_at => DateTime.now}
      else
        m.reply "#{m.user.nick}: Can't override a user's self-definition."
        return
      end
    else
      friend_codes[username.downcase] = {:friend_code => friend_code, :added_by => m.user.nick.downcase, :updated_at => DateTime.now}
    end
    # write it to the file
    output = File.new(@pddata, 'w')
    output.puts YAML.dump(friend_codes)
    output.close

    m.reply "#{m.user.nick}: #{mangle(username)} successfully added as '#{friend_code}'."
  end

  def pazudora_remove(m, args)
    pargs = args.split
    username = pargs[0]
    friend_codes = load_data || {}

    if !friend_codes[username]
      m.reply "#{m.user.nick}: #{mangle(username)} not in friend code list."
      return
    end

    if (m.user.nick.downcase == username.downcase) || (m.user.nick.downcase == friend_codes[username][:added_by])
      friend_codes.delete(username)
      # write it to the file
      output = File.new(@pddata, 'w')
      output.puts YAML.dump(friend_codes)
      output.close

      m.reply "#{m.user.nick}: #{mangle(username)} removed from friend code list."
    else
      m.reply "#{m.user.nick}: Only the identity creator or subject can remove a friend code from the list."
    end
  end

  def pazudora_who(m,args)
    pargs = args.split
    username = pargs[0]
    if load_data[username.downcase]
      m.reply "#{m.user.nick}: #{mangle(username)}'s friend code is #{load_data[username.downcase][:friend_code]}"
    end
  end

  def pazudora_list(m,args)
    friend_codes = load_data || {}
    friend_codes.keys.each_slice(3).with_index { |users, i|
      r = i == 0 ? "#{m.user.nick}: " : ""
      users.each{ |user| r=r+"#{mangle(user)}:#{friend_codes[user][:friend_code]} " }
      m.reply r
    }
  end

  def pazudora_group(m,args)
    pargs = args.split
    username = pargs[0]
    if load_data[username.downcase]
      friend_code = load_data[username.downcase][:friend_code]
      group = (Integer(friend_code.split(",")[0][2]) % 5 + 65).chr
      m.reply "#{m.user.nick}: #{mangle(username)}'s group is #{group}"
    else
      m.reply "#{m.user.nick}: #{mangle(username)}'s friend code is not listed. Please use the add command to add it."
    end
  end

  def pazudora_dailies(m, args)
		m.reply(get_dailies.join(' '))
	end

	
	def pazudora_settopic(m, args)
		m.channel.topic = (get_dailies + m.channel.topic.split(' ').drop((m.channel.topic.split(' ').index("||") || -1) + 1)).join(' ')
	end
	
	def get_dailies
		daily_url = PUZZLEMON_BASE_URL + "option.asp?utc=-8"

		@daily_page = Nokogiri::HTML(open(daily_url))
		event_data = @daily_page.css(".event3")
		event_rewards = @daily_page.css(".limiteddragon")

		rewards = parse_daily_dungeon_rewards(event_rewards)

		dailies_array = []
		dailies_array.push(Time.now.strftime "%b %d, %Y")
		
		hacky_dailies_number = [rewards.length - 1, 3].min # this is NOT optimal and makes some ugly assumptions
		
		(0..hacky_dailies_number).each do |i|
			dailies_array.push('|')
			dailies_array.push(rewards[i])
			(0..4).each do |j|
				time = "#{event_data[5 * i + j].text}"
				hour = time.split(" ")[0].to_i
				hour = 0 if (hour == 12)
				hour += 12 if time.split(" ")[1] == "pm"
				dailies_array.push(hour.to_s.rjust(2,'0'))
			end
		end

		dailies_array.push("||")
		return dailies_array
	end
	
  def pazudora_when(m, args)

    username = args.split[0] || m.user.nick
    friend_code = load_data[username.downcase][:friend_code] rescue nil
    group_num = friend_code ? group_number_from_friend_code(friend_code) : nil
    unless group_num
      m.reply "Unrecognized user."
      return
    end
 
	dailies_array = get_dailies
    minutes_since_midnight = ((Time.now.to_i - 7*60*60) % 86400)/60
	when_array = [dailies_array[0], "Group", (group_num + 65).chr, dailies_array[1]]
	i = 2
    while dailies_array[i]
		when_array += [dailies_array[i]]
		until_event = 60*dailies_array[i+group_num+1].to_i - minutes_since_midnight
		if until_event > 0
			when_array += ["(in #{until_event / 60}:#{(until_event % 60).to_s.rjust(2,'0')}, #{until_event / 10} stamina)"]
		elsif until_event > -60
			when_array += ["(now! for #{until_event+60} minutes)"]
		else
			when_array += ["(done)"]
		end
		
		when_array += ["|"]
		i += 7
	end
	
	when_array.pop
	m.reply(when_array.join(' '))
  end
		
		



  def enqueue_dailies(channel)
    daily_url = PUZZLEMON_BASE_URL + "option.asp?utc=-8"

    unless @daily_timestamp == Time.now.strftime("%m-%d-%y")
      @daily_page = nil
      @daily_timestamp = Time.now.strftime("%m-%d-%y")
    end

    @daily_page ||= Nokogiri::HTML(open(daily_url))
    event_data = @daily_page.css(".event3")
    event_rewards = @daily_page.css(".limiteddragon")
    rewards = parse_daily_dungeon_rewards(event_rewards)
    count = 0

    (0..4).each do |i|
      group = "Group #{(i + 65).chr}"
      times = []
      frame = 0
      loop do
        break if event_data[i + frame].nil?
        hour,am_pm = event_data[i + frame].text.split
        hour = hour.to_i + (am_pm == "pm" ? 12 : 0)
        t = DateTime.strptime("#{hour}:00-7:00", "%H:%M%z").to_time
        p "enqueuing #{group} to #{channel} at #{t}"
        @alarms << {:time => t, :text => rewards.first, :channel => channel, :user => group}
        count += 1
        frame += 5
      end
    end

    count
  end

  def pazudora_lookup(m, args)
    identifier = args
    pdx = PazudoraData.instance.get_puzzlemon(identifier)
    m.reply "Could not find puzzlemon #{identifier}" and return if pdx.nil?
    m.reply pdx.lookup_output
  end

  def pazudora_shortdungeon(m, args)
    identifier = args
    output = PazudoraData.instance.get_dungeon(identifier)
    m.reply "Could not find dungeon #{identifier}" and return if output.nil?
    m.reply output.split("\n").first
  end

  def pazudora_dungeon(m, args)
    identifier = args
    output = PazudoraData.instance.get_dungeon(identifier)
    if output.nil?
      dungeonset = PazudoraData.instance.get_dungeonset(identifier)
      name = PazudoraData.instance.match_dungeonset_name(dungeonset)
      m.reply "No matches for ID #{identifier}" and return if dungeonset.nil?
      m.reply "ID #{name} is associated with the following dungeonset: "
      collector = []
      dungeonset.each do |id, name|
        collector << "##{id}: #{name}"
      end
      m.reply collector.join(', ') + "."
    elsif output.split("\n").length > 4
      m.reply "Could not find dungeon #{identifier}" and return if output.nil?
      m.reply "Found data on #{identifier}, uploading to Gist..."
      gist = Gist.gist(output, :filename => "dungeon_data.txt")
      url = gist["files"].first.last["raw_url"]
      size = gist["files"].first.last["size"] 

      bitly = Bitly.new("asterismsa", "R_b02766a585a99ba34687db69d5ab1ddf")
      u = bitly.shorten(url)
      m.reply("#{size} bytes of dungeon data uploaded to #{u.short_url}")
    else
      m.reply(output)
    end
  end

  def pazudora_chain(m, args)
    identifier = args
    pdx = PazudoraData.instance.get_puzzlemon(identifier)
    m.reply "Could not find puzzlemon #{identifier}" and return if pdx.nil?
    m.reply pdx.chain_output
  end

  def pazudora_evolution(m, args)
    identifier = args
    pdx = PazudoraData.instance.get_puzzlemon(identifier)
    m.reply "Could not find puzzlemon #{identifier}" and return if pdx.nil?
    m.reply pdx.mats_output.gsub("\n", ", ").gsub(":,",":").gsub(/No.\d+ /, "")
  end

  def pazudora_experience(m, args)
    argv = args.split(" ")
    if is_numeric?(argv.last)
      from = argv.pop.to_i
    else
      from = 1
    end
    identifier = args
    pdx = PazudoraData.instance.get_puzzlemon(identifier)
    m.reply "Could not find puzzlemon #{identifier}" and return if pdx.nil?
    m.reply pdx.experience_output(from)
  end

  def pazudora_time(m, args)
    argv = args.split(" ")
    if argv.last.match(/(\+|\-)\d+/)
      timezone = argv.pop
      offset = timezone.to_i
      offset = offset * -1 if offset < 0
      if offset > 0 && offset < 10
        offset = "0#{offset}"
      elsif offset >= 24
        m.reply "Invalid UTC offset #{offset}" and return
      else
        offset = offset.to_s
      end
      utc = "#{timezone[0,1]}#{offset}:00"
    else
      utc = "-07:00"
    end

    if argv.length == 1
      given_time = argv.first
      current_stamina = 0
    elsif argv.length == 2
      given_time = argv.last
      current_stamina = argv.first.to_i
    else
      m.reply "USAGE: !pad time HH:MM TIMEZONE?" and return
    end

    t = DateTime.strptime(given_time + utc, "%H:%M%z").to_time
    delta = t - Time.now
    delta = (delta > 0) ? delta : delta + 86400
    stamina = (delta / (60 * 10)).round

    if current_stamina == 0
      r = "By #{t.getlocal(utc).strftime("%I:%M%p")} UTC#{utc}, you will have gained #{stamina} stamina"
    else 
      r = "By #{t.getlocal(utc).strftime("%I:%M%p")} UTC#{utc}, you will have gained #{stamina} stamina, for a total of #{current_stamina + stamina}"
    end
    m.reply r
  end

  def pazudora_stamina(m, args)
    argv = args.split(" ")
    if argv.last.match(/(\+|\-)\d+/)
      timezone = argv.pop
      offset = timezone.to_i
      offset = offset * -1 if offset < 0
      if offset > 0 && offset < 10
        offset = "0#{offset}"
      elsif offset >= 24
        m.reply "Invalid UTC offset #{offset}" and return
      else
        offset = offset.to_s
      end
      utc = "#{timezone[0,1]}#{offset}:00"
    else
      utc = "-07:00"
    end

    argv = argv.map(&:to_i)
    if argv.length == 2
      from = argv.first
      to = argv.last
    elsif argv.length == 1
      from = 0
      to = argv.last
    else
      m.reply "USAGE: !pad stamina TO? FROM TIMEZONE?" and return
    end

    stamina_delta = to - from
    time_delta = stamina_delta * 60 * 10
    target_time = Time.now + time_delta
    target_time = target_time.getlocal(utc)
    r = "You will gain #{stamina_delta} stamina (#{from}-#{to}) in ~#{stamina_delta * 10} minutes," +
        target_time.strftime(" or around %I:%M%p UTC") + utc
    m.reply r
  end

  def pazudora_gacha(m, args)
    argv = args.split(" ")
    if !argv.last.nil? && argv.last.match(/\+\S+/)
      godfest_flags = argv.last.split(//)[1..-1].map(&:upcase)
      args = args.split("+").first.strip
    else
      godfest_flags = []
    end

    if args == "tags" || args == "list_tags"
      r = "Use +[tags] to denote godfest; for example !pad pull +JGO for a japanese/greek/odins fest.\n"
      r += "Known tags: [R]oman, [J]apanese, [H]indu or [I]ndian, [N]orse, [E]gyptian, [G]reek, [O]dins, [A]ngels, [Devils]"
      m.reply r
    elsif is_numeric?(args)
      gods = []
      args.to_i.times do
        pdx = PazudoraData.instance.gachapon(godfest_flags)
        stars = pdx.stars
        type = pdx.type
        name = pdx.name
        if stars >= 5 && type == "god" && !pdx.name.include?("Verche")
          gods << pdx.name
        end
      end
      overflow = 0
      if gods.length > 10
        overflow = gods.length - 10
        gods = gods[0..9]
      end
      price = stone_price(args.to_i * 5)
      if gods.length == 0
        r = "You rolled #{args} times (for $#{price}) and got jackshit all. Gungtrolled."
      else
        r = "You rolled #{args} times (for $#{price}) and got some gods:\n"
        r += gods.join(", ")
        if overflow > 0
          r += "...and #{overflow} more"
        end
      end
      m.reply r
    elsif args == ""
      pdx = PazudoraData.instance.gachapon(godfest_flags)
      stars = pdx.stars
      type = pdx.type
      name = pdx.name

      if name.include?("Golem") || name.include?("Guardian")
        golem = true
        name = e_a_r_t_h_g_o_l_e_m(name)
      end

      if stars >= 5 && type == "god" && !pdx.name.include?("Verche")
        msg =  (stars == 6 ? "Lucky bastard!" : "Lucky bastard.")
      elsif stars == 5
        msg = "Meh."
      elsif golem
        msg = "Y O U I D I O T."
      else
        msg = "I just saved you $5."
      end
      r = "You got #{name}, a #{stars}* #{type}. #{msg}"
      m.reply(r)
    else
      regex = false
      identifier = args.strip.downcase
      if identifier.match(/\A\/.*\/\z/)
        regex = true
        identifier = Regexp.new("#{identifier[1..-2]}")
      end
      attempts = 0
      pdx = nil
      loop do
        attempts = attempts + 1
        pdx = PazudoraData.instance.gachapon(godfest_flags)
        next unless pdx.valid?
        break if !regex && (pdx.name.downcase.include?(identifier) || pdx.id == identifier)
        break if regex && (pdx.name.downcase.match(identifier) || pdx.name.match(identifier))
        m.reply("Unable to roll #{identifier}") and return if attempts == 10000
      end
      price = stone_price(attempts * 5)
      m.reply("After #{attempts} attempts, you rolled a #{pdx.name}. (There goes $#{price})")
    end
  end

  def pazudora_rank(m, args)
    argv = args.split(" ")
    if argv.length == 1
      data = rank_data[argv.first]
      m.reply("No data for rank #{argv.first}") and return unless data
      r = "Rank #{argv.first}: cost #{data[:cost]}, stamina #{data[:stamina]}, friends #{data[:friends]}, total experience #{data[:exp_total]}, next level #{data[:exp_next]}"
      r.gsub!("--", "??")
    elsif argv.length == 2 && ["cost", "stamina", "friends"].include?(argv.first)
      search_stat = argv.first.to_sym
      m.reply("Bad search value #{argv.last}") and return unless is_numeric?(argv.last)
      search_value = argv.last.to_i
      rank_data.each do |k, v|
        if v[search_stat].to_i >= search_value
          m.reply("You will get >= #{search_value} #{search_stat} at rank #{k}") and return
        end
      end
      m.reply("Unable to reverse lookup #{search_value} #{search_stat}") and return
    elsif argv.length == 2
      data = rank_data
      input = argv.map(&:to_i).sort
      alpha = data[input.first.to_s]
      omega = data[input.last.to_s]
      exp_data_missing = input.last >= 148

      delta_cost = omega[:cost].to_i - alpha[:cost].to_i
      delta_stamina = omega[:stamina].to_i - alpha[:stamina].to_i
      delta_friends = omega[:friends].to_i - alpha[:friends].to_i

      r = "Ranks #{input.first}-#{input.last}: cost +#{delta_cost}, stamina +#{delta_stamina}, friends +#{delta_friends}"

      if exp_data_missing
        r += ".\nWarning: PDX experience values missing for ranks >= 148"
      else
        delta_exp = omega[:exp_total].to_i - alpha[:exp_total].to_i
        r += ", experience +#{delta_exp}."
      end
    else
      r = "Usage: !pad rank n for data about rank n, !pad rank x y to compute deltas between x and y, !pad <field> n for reverse lookup"
    end
    m.reply(r)
  end

  protected
  def is_numeric?(str)
    begin
      !!Integer(str)
    rescue ArgumentError, TypeError
      false
    end
  end

  # convert a requirements td into a list of evolution materials
  def evo_material_list(td)
    material_elements = td.children.select{|element| element.name == "a"}
    material_elements.map do |element|
      element.children.first.attributes["title"].value
    end
  end

  def stone_price(stones)
    prices = {1 => 1, 6 => 5, 12 => 10, 30 => 23, 60 => 44, 85 => 60}
    money = 0
    while stones > 0
      selection = prices.keys.select{|x| x <= stones}.max
      stones = stones - selection
      money = money + prices[selection]
    end
    money
  end

  def rank_data
    ranks = Nokogiri::HTML.parse(open(RANK_TABLE_URL).read)
    rows = ranks.xpath("//table[@id='tablechart']").first.children
    rv = {}
    rows[2..-1].each do |row|
      cells = row.children
      level = cells[0].children.to_s
      cost = cells[1].children.to_s
      stamina = cells[2].children.to_s
      friends = cells[3].children.to_s
      exp_total = cells[4].children.to_s
      exp_next = cells[5].children.to_s
      rv[level] = {cost:cost,
                   stamina:stamina,
                   friends:friends,
                   exp_total:exp_total,
                   exp_next:exp_next}
    end
    rv
  end

  def mangle(s)
    s.chop + "." + s[-1]
  end

  def e_a_r_t_h_g_o_l_e_m(s)
    out = ""
    s.each_char do |chr|
      next if chr == " "
      out += chr.upcase
      out += " "
    end
    out.strip
  end

  def load_data
    datafile = File.new(@pddata, 'r')
    friend_codes = YAML.load(datafile.read)
    datafile.close
    return friend_codes
  end

  def group_number_from_friend_code(friend_code)
    return Integer(friend_code.split(",")[0][2]) % 5
  end

def parse_daily_dungeon_rewards(rewards)
    
	puzzlemon_numbers = []
	i = 0
	while rewards[i] != nil
		puzzlemon_numbers += [rewards[i].children.first.attributes["src"].value.match(/thumbnail\/(\d+).png/)[1]]
		i += 5
	end

    puzzlemon_numbers.map{|x|
      get_puzzlemon_info(x).css(".name").children.first.text rescue "Unrecognized Name" }
  end

  def get_puzzlemon_info(name_or_number)
    search_url = PUZZLEMON_BASE_URL + "monster.asp?n=#{name_or_number}"
    puzzlemon_info = Nokogiri::HTML(open(search_url))
  end
end


