require 'open-uri'
require 'nokogiri'
require 'pry'
require 'json'

PDX_MONSTER_COUNT = 683

class Puzzlemon
  PUZZLEMON_BASE_URL = "http://www.puzzledragonx.com/en/"
  GACHA_URL = "http://www.puzzledragonx.com/egg.asp"

  # given an XP curve page, return the XP required to hit a level from 0
  def self.xp_at_level(curve_page, level)
    all_elements = curve_page.xpath("//table[@id='tablechart']//tbody//td")
    rows = curve_page.xpath("//table[@id='tablechart']//tbody//td[@class='blue']")
    row_index = all_elements.index(rows.select{|h| h.text == level.to_s}.first)
    all_elements[row_index + 1].text.to_i
  end

  def self.xp_to_level(curve_page, from, to)
    begin
      xp_at_level(curve_page, to) - xp_at_level(curve_page, from)
    rescue NoMethodError
      nil
    end
  end

  def initialize(identifier, gacha=false)
    if gacha
      @doc = gacha_page
    else
      @doc = pdx_page_from_identifier(identifier)
    end
  end

  def gacha_page
    Nokogiri::HTML.parse(open(GACHA_URL).read)
  end

  def valid?
    !@doc.nil?
  end

  def noko
    @doc
  end

  def experience_delta(from)
    links = @doc.xpath("//a").map{|element| element.attributes["href"]}.compact
    curve_link = links.select{|link| link.value.include?("experiencechart")}.first
    curve_page = Nokogiri::HTML(open(PUZZLEMON_BASE_URL + curve_link.value))
    Puzzlemon.xp_to_level(curve_page, from, max_level)
  end

  # given an id or monster name, uses pdx's fuzzy matcher to find the pdx
  # page for the referenced monster. Returns nil if the fuzzy matcher returns
  # nothing e.g meteor dragon what the fuck seriously jesus christ
  def pdx_page_from_identifier(identifier)
    search_url = PUZZLEMON_BASE_URL + "monster.asp?n=#{URI.encode(identifier)}"
    info = Nokogiri::HTML(open(search_url))

    #Bypass puzzledragonx's "default to meteor dragon if you can't find the puzzlemon" mechanism
    meteor_dragon_id = "211"
    if info.css(".name").children.first.text == "Meteor Volcano Dragon" && !(identifier.start_with?("Meteor") || identifier == meteor_dragon_id)
      return nil
    else
      return info
    end
  end

  def pdx_descriptor
    @doc.css("meta [name=description]").first.attributes["content"].text
  end

  # grab the name of a monster from its page the stupid way
  def name
    @doc.css(".name").children.first.text
  end

  # find the URL of the image of the monster, and parse it for the monster's id
  def id
    avatar_image = @doc.xpath("//div[@class='avatar']").first.children.first
    path = avatar_image.attributes["src"].value
    /img\/book\/(\d+)\.png/.match(path)[1]
  end

  # given a pazudora info page, find the max level of the monster
  def max_level
    lookup_stat("Level:").last
  end

  def max_xp
    match = @doc.to_s.scan(/((\d|,)+) Exp to max/)
    begin
      return match[0][0]
    rescue NoMethodError
      return 0
    end
  end

  def stat_line(stat_name)
    minmax = lookup_stat(stat_name + ":")
    "#{minmax.first}-#{minmax.last}"
  end

  def lookup_stat(stat_name)
    row = @doc.xpath("//table[@id = 'tablestat']//td[@class = 'title']").
        select{|x| x.text == stat_name}.first
    siblings = row.parent.children
    [siblings[1].text.to_i, siblings[2].text.to_i]
  end

  def skill
    link = @doc.xpath("//a").select{|link| link.attributes["href"] && link.attributes["href"].
        value.match(/\Askill.asp?/)}.first
    return "No active skill.\n" if link.nil?
    name = link.children.first.text
    lines = link.parent.parent.parent.children.map(&:text)
    index = lines.index("Skill:#{name}")

    skillname = lines[index].split(":").last
    cooldowns = lines.select{|l| l.include? "Cool Down"}.first
    cooldowns = cooldowns.scan(/Cool Down:(\d+) Turns \( (\d+) minimum \)/).first
    cooldowns = "(#{cooldowns.last}-#{cooldowns.first} turns)"

    if lines[index + 3].include?("Leader Skill")
      effect = lines[index + 1].split(":").last
    else
      effect = lines[index + 2].tr(')', '').tr('(', '')
    end

    "(Active) #{skillname}: #{effect.strip} #{cooldowns}\n"
  end

  def leaderskill
    link = @doc.xpath("//a").select{|link| link.attributes["href"] && link.attributes["href"].
        value.match(/\Aleaderskill.asp?/)}.first
    return "No leader skill.\n" if link.nil?
    name = link.children.first.text
    lines = link.parent.parent.parent.children.map(&:text)
    index = lines.index("Leader Skill:#{name}")
    if lines[index + 2]
      effect = lines[index + 2].tr(')', '').tr('(', '')
    else
      effect = lines[index + 1].split(":").last
    end

    "(Leader) #{name}: #{effect}"
  end

  def stars
    @doc.xpath("//div[@class='stars']//img").count
  end

  def element
    desc = pdx_descriptor
    desc.scan(/is a (.*?) element monster/)[0][0]
  end

  def cost
    desc = pdx_descriptor
    desc.scan(/costs (\d+?) units/)[0][0]
  end

  def type
    desc = pdx_descriptor
    desc.scan(/stars (.*?) monster/)[0][0]
  end

  def get_puzzledex_description
    r = "No. #{id} #{name}, a #{stars}* #{element} #{type} monster.\n"
    r += "Deploy Cost: #{cost}. Max level: #{max_level}, #{max_xp} XP to max.\n"
    r += "HP #{stat_line("HP")}, ATK #{stat_line("ATK")}, RCV #{stat_line("RCV")}, BST #{stat_line("Total")}\n"
    r += "#{skill}"
    r += "#{leaderskill}"
    r
  end
end

def chain(pdx)
  info = pdx.noko

  # Compute the ID numbers of the puzzlemons in this particular chain
  chain_divs = info.xpath("//td[@class='evolve']//div[@class='eframenum']")
  chain_members = chain_divs.map{|div| Puzzlemon.new(div.children.first.text).name}
  # Check whether there is a multi-choice ultimate evolution
  ultimate_count = info.xpath("//td[@class='finalevolve']").length
  if ultimate_count > 1
    ((-1 * ultimate_count)..-1).step do |n|
      chain_members[n] = "\t#{chain_members[n]} (busty)"
    end
  end
  chain_members
end

def mats(pdx)
  info = pdx.noko

  # Compute the ID numbers of the puzzlemons in this particular chain
  chain_divs = info.xpath("//td[@class='evolve']//div[@class='eframenum']")
  chain_members = chain_divs.map{|div| div.children.first.to_s}

  # Compute the location of the current puzzlemon in the chain
  requirements = info.xpath("//td[@class='require']")
  busty_requirements = info.xpath("//td[@class='finalevolve']")
  ultimate_count = busty_requirements.count
  index = chain_members.index(pdx.id)

  if index == requirements.length && ultimate_count > 0
    busty_requirements.map{|r| evo_material_list(r)}
  elsif index.nil? || requirements.nil? || index >= requirements.length
    []
  else
    evo_material_list(requirements[index])
  end
end

def evo_material_list(td)
  material_elements = td.children.select{|element| element.name == "a"}
  material_elements.map do |element|
    element.children.first.attributes["title"].value
  end
end

def exp_curve(pdx)
    links = pdx.noko.xpath("//a").map{|element| element.attributes["href"]}.compact
    curve_link = links.select{|link| link.value.include?("experiencechart")}.first
    return nil if curve_link.nil?
    out = curve_link.value.scan(/.*?(\d+).*?/).first.first
    p out
  out
end

def build_monster_book()
  collector = scrape_monsters((1..PDX_MONSTER_COUNT))
  f = File.open("scraped_monsters.json", "w")
  f.write(collector.to_json)
  f.close 
end

def add_monster_book(from, to)
  collector = scrape_monsters((from..to))
  old_file = File.open("db/scraped_monsters.json", "r")
  old_book = JSON.parse(old_file.read)
  binding.pry
  new_book = old_book.merge(collector)
  f = File.open("scraped_monsters_new.json", "w")
  f.write(new_book.to_json)
  f.close 
end

def scrape_monsters(iter)
  collector = {}
  iter.step do |n|
    begin
      pdx = Puzzlemon.new(n.to_s)
      next unless pdx.valid?
      name = pdx.name
      max_level = pdx.max_level
      max_xp = pdx.max_xp.to_i
      skill_text = pdx.skill
      leader_text = pdx.leaderskill
      stars = pdx.stars
      element = pdx.element
      cost = pdx.cost.to_i
      type = pdx.type
      hp_min = pdx.lookup_stat("HP:").first
      hp_max = pdx.lookup_stat("HP:").last
      atk_min = pdx.lookup_stat("ATK:").first
      atk_max = pdx.lookup_stat("ATK:").last
      rcv_min = pdx.lookup_stat("RCV:").first
      rcv_max = pdx.lookup_stat("RCV:").last
      bst_min = pdx.lookup_stat("Total:").first
      bst_max = pdx.lookup_stat("Total:").last
      evo_chain = chain(pdx)
      evo_mats = mats(pdx)
      curve = exp_curve(pdx)
      collector[n] = {
          :name => name,
          :max_level => max_level,
          :max_xp => max_xp,
          :skill_text => skill_text,
          :leader_text => leader_text,
          :stars => stars,
          :element => element,
          :cost => cost,
          :type => type,
          :hp_min => hp_min,
          :hp_max => hp_max,
          :atk_min => atk_min,
          :atk_max => atk_max,
          :rcv_min => rcv_min,
          :rcv_max => rcv_max,
          :bst_min => bst_min,
          :bst_max => bst_max,
          :evo_chain => evo_chain,
          :evo_mats => evo_mats,
          :curve => curve
      }
      p "Scraped no.#{n} #{name}"
      sleep(0.1)
    rescue Exception => e
      p e
      p e.backtrace
    end
  end

  collector
end

def scrape_xp_page(uri)
  curve_page = Nokogiri::HTML(open(uri))
  collector = {}
  (1..99).step do |level|
    all_elements = curve_page.xpath("//table[@id='tablechart']//tbody//td")
    rows = curve_page.xpath("//table[@id='tablechart']//tbody//td[@class='blue']")
    row_index = all_elements.index(rows.select{|h| h.text == level.to_s}.first)
    collector[level] = all_elements[row_index + 1].text.to_i
  end
  collector
end

def scrape_xp()
  collector = {}
  base = "http://www.puzzledragonx.com/en/experiencechart.asp?c="
  ["1000000","1500000","2000000","3000000","4000000","5000000"].each do |curve|
    collector[curve] = scrape_xp_page(base + curve)
  end
  f = File.open("scraped_xp_curves.json", "w")
  f.write(collector.to_json)
  f.close
end

def scrape_dungeonsets()
  base = "http://www.puzzledragonx.com/en/dungeon.asp?d="
  collector = {}
  (1..150).step do |n|
    doc = Nokogiri::HTML.parse(open(base + n.to_s).read)
    next if doc.to_s.include?("Meteor Volcano Dragon is a fire element monster")
    header = doc.to_s.scan(/<h1>(.+)<\/h1>/).first.first
    dungeons = doc.to_s.scan(/<a href="mission.asp\?m=(\d+)">(.+)<\/a>/)
    collector[header] = dungeons
    p "Scraped #{header}"
  end
  f = File.open("scraped_dungeonsets.json", "w")
  f.write(collector.to_json)
  f.close
end

def scrape_dungeons()
  base = "http://www.puzzledragonx.com/en/mission.asp?m=" 
  collector = {}
  (1..500).step do |n|
    doc = Nokogiri::HTML.parse(open(base + n.to_s).read)
    next if doc.to_s.include?("Meteor Volcano Dragon is a fire element monster")
    name, data = scrape_dungeon(doc, n)
    collector[name] = data
  end
  f = File.open("scraped_dungeons.json", "w")
  f.write(collector.to_json)
  f.close
end

def scrape_dungeon(doc, n)
  p "Scraping dungeon #{n}"
  stats = doc.xpath("//table[@id='tablestat']").first.children.children
  dungeon_name = stats[2].content
  stamina = stats[6].content
  battles = stats[10].content
  gold = stats[13].content
  experience = stats[16].content
  header = "(#{n}) #{dungeon_name}: #{stamina} stamina, #{battles} battles."
  header += " #{gold}G." if gold
  header += " #{experience}EXP." if experience
  header += " #{(1.0 * experience.to_i)/stamina.to_i}E/S." if (gold and experience)

  fixed_encounters_header = doc.xpath("//h2").select{|h| h.content == "Major Encounters"}.first
  fixed_encounters_table = fixed_encounters_header.parent.parent.parent.parent
  bosses = fixed_encounters_table.children.children.select{|node| node.name == "td" && node.attributes["class"].to_s == "enemy"}
  boss_data = []

  bosses.each do |boss|
    siblings = boss.parent.children
    floor = siblings[0].children.text
    enemy = siblings[2].children.text
    cd = siblings[3].children.text  
    damage = siblings[4].children.text
    defense = siblings[5].children.text
    hp = siblings[6].children.text
    next if boss.parent.children[10].nil?
    techs = boss.parent.children[10].children.map(&:text).select{|t| t.length > 3}
    techs = techs.map{|t| t.gsub(/\s*\(\s*/, "(").gsub(/\s*\)\s*/,")")}
    text = "#{floor}: #{enemy}: #{hp} HP, #{defense} DEF. #{damage}/#{cd} turn"
    text += cd == 1 ? "." : "s."
    text += " T: #{techs.join(', ')}" if techs.length > 0
    boss_data << text
  end

  [dungeon_name, ([header] + boss_data).join("\n")]
end

binding.pry
