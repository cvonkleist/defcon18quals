# for 2010 defcon quals (18) by cvk
# 6af3db1bb81f2d056d3ae59d61c589bb
require 'protocol'
require 'irb'
require 'ruby-debug'

# this is stupid
NAMES = Hash.new(:unknown).merge({
  '1bcfa892701c00ce76d4cb717068dfd6011a49e5' => 'Steve Jobs',
  'ab74176394caeb1158df9c4d9fac004fff27377a' => 'ac1dburn',
  '5270abbc1f4475f6df2ef42f106a99110c87314d' => 'Eric S. Raymond',
  'c9c074ad228c2ea8aedc4d72d79bb53c99e90716' => 'War Games kid',
  'ca8d2c2f7845e635fec4632be8235d5f8bcde287' => 'Don Knuth',
  'd47bbd64a725d88b54518ae1c768fc4855c80972' => 'zero_cool',
  '39ddc6e687b0cd8255ea44a0a9a7b2cb88601454' => 'Wietse Venema',
  '9c476365fac9a87bb1f7d863e5af42b42169d986' => 'Cory Doctorow',
  '6a6f1e41d76bf1d2434e126ba3f973f6d14457c7' => 'Jennifer Granick',
  '7bdb1a04865e8afda31a574bba7e0519c16c0c2d' => 'Neo',
  '60a866620633b2fbe379ff9ac1c837b81d1a9b32' => 'Fyodor'
})

class Hacker
  attr_reader :name, :hacker_id
  def initialize(hacker_id, all_matches)
    @hacker_id = hacker_id
    @all_matches = all_matches
  end

  # array of matches this hacker has won
  def won_matches
    @all_matches.select do |m|
      m[:winner] == self
    end
  end

  # array of matches this hacker has lost
  def lost_matches
    @all_matches.select do |m|
      m[:loser] == self
    end
  end

  # true if this hacker has had a match with +hacker+
  def has_met?(hacker)
    defeated.include?(hacker) || defeated_by.include?(hacker)
  end

  # array of hackers beaten by this hacker
  def defeated
    @defeated ||= won_matches.collect do |m|
      m[:loser]
    end.uniq
  end

  # array of hackers this hacker has lost to
  def defeated_by
    @defeated_by ||= lost_matches.collect do |m|
      m[:winner]
    end.uniq
  end

  # wins-to-losses ratio
  def score
    raise "big error" if defeated - defeated_by != defeated # ridiculous sanity check
    wins.to_f / losses
  end

  # number of hackers this hacker has beaten
  def wins
    defeated.length
  end

  # number of hackers this hacker has lost to
  def losses
    defeated_by.length
  end

  def name
    NAMES[@hacker_id]
  end

  # all the hackers this hacker has beaten, and all the hackers that hacker has
  # beaten, and so on
  def superiors(skip = [])
    @superiors ||= (defeated_by - skip).collect do |h|
      skip << h
      [h, h.superiors(skip)]
    end.flatten.uniq
  end

  # true if there's no data saying this hacker couldn't beat +hacker+
  def could_defeat?(hacker)
    !superiors.include?(hacker)
  end

  # true if this hacker can definitely beat +hacker+
  #
  # (if any hacker that this hacker has beaten has beaten any hacker that has
  # beaten +hacker+, this is true)
  def will_defeat?(hacker)
    hacker.superiors.include?(self)
  end

  # when there's no way to be sure, use statistics
  def will_probably_defeat?(hacker)
    score > hacker.score
  end

  def inspect
    '<Hacker:%s hacker_id="%s" name=%s>' % [object_id, @hacker_id, name.inspect]
  end

  # when SmartGame learns a new match, these cached values must be recalculated
  def clear_cache!
    @superiors = @defeated = @defeated_by = nil
  end
end

class SmartGame < Game
  attr_reader :hackers
  def initialize
    super
    @hacker_matches = []
    @good_guesses = @bad_guesses = 0
    @sequence = ''
  end

  # read gamelog and build hackers
  def educate
    hackers = {}
    File.read(GAMELOG).split("\n").each do |line|
      unless line.match(' beat ')
        puts "bad line: " + line.inspect
        next
      end
      winner_id, loser_id = line.split(' beat ')
      hackers[winner_id] = winner = hackers[winner_id] || Hacker.new(winner_id, @hacker_matches)
      hackers[loser_id] = loser = hackers[loser_id] || Hacker.new(loser_id, @hacker_matches)

      @hacker_matches << {:winner => winner, :loser => loser}
    end
    @hackers = []
    hackers.each do |hacker_id, hacker|
      @hackers << hacker
    end
    debug 'loaded %d hackers' % @hackers.length
  end

  # given two hackers, predict which will win
  def predict_winner(hacker1, hacker2)
    if hacker1.will_defeat?(hacker2)
      debug ' hacker1 will defeat hacker2'
      hacker1
    elsif hacker2.will_defeat?(hacker1)
      debug ' hacker2 will defeat hacker1'
      hacker2
    elsif hacker1.will_probably_defeat?(hacker2)
      debug ' hacker1 will probably defeat hacker2'
      hacker1
    else # hacker2.will_probably_defeat?(hacker2) is true in this case
      debug ' hacker2 will probably defeat hacker2'
      hacker2
    end
  end

  def get_new_hackers
    super
    # if we haven't seen either hacker before, make new objects for them
    [@hacker_id1, @hacker_id2].each do |hacker_id|
      @hackers << Hacker.new(hacker_id, @hacker_matches) unless already_seen?(hacker_id)
    end
  end

  # use predict_winner to choose between the hackers the server sent
  def move
    hacker1 = hacker_by_id(@hacker_id1)
    hacker2 = hacker_by_id(@hacker_id2)

    choice = predict_winner(hacker1, hacker2)

    if choice == hacker1
      @sequence += "L"
      @sock.write "\000"
      debug 'picking hacker1'
      @last_move = {:chosen => @hacker_id1, :not_chosen => @hacker_id2}
    else
      @sequence += "R"
      @sock.write "\001"
      debug 'picking hacker2'
      @last_move = {:chosen => @hacker_id2, :not_chosen => @hacker_id1}
    end

    @matches << @last_move
  end

  def status
    puts '@sequence = ' + @sequence.inspect + ' (%d)' % @sequence.length
    puts 'i know about %d hacker matches' % @hacker_matches.length
    show_guess_stats
  end

  def show_guess_stats
    debug 'guessing accuracy == %6.2f%%' % (100.0 * accuracy)
  end
  def accuracy
    (@good_guesses + @bad_guesses) > 0 ? @good_guesses.to_f / (@good_guesses + @bad_guesses) : 0
  end

  def log(match)
    super
    @hacker_matches << {:winner => hacker_by_id(match[:winner]), :loser => hacker_by_id(match[:loser])}
  end

  # called when we get a guess right
  def good_guess
    super
    puts
    @good_guesses += 1
    clear_hacker_caches
  end

  def sequence
    @sequence
  end

  # called when we get a guess wrong
  def bad_guess
    super
    puts
    @bad_guesses += 1
    @sequence = '' # @sequence[-1,1]
    clear_hacker_caches
  end

  # when we learn a new match, the hackers' cached stats need to be forgotten
  def clear_hacker_caches
    @hackers.each { |h| h.clear_cache! }
  end

  ## beyond this point is stuff i used for testing while writing this script

  # have we already created a hacker object for this hacker id?
  def already_seen?(hacker_id)
    hacker_ny_name(hacker_id).nil? rescue false
  end

  def hacker_by_name(name)
    @hackers.find { |h| h.name == name }
  end
  def hacker_by_id(hacker_id)
    h = @hackers.find { |h| h.hacker_id == hacker_id }
    raise 'id ' + hacker_id + ' not found' unless h
    h
  end
  def hackers_by_rank
    @hackers.sort { |h1, h2| h2.score <=> h1.score }
  end
  def show_hacker_rankings
    puts %w(rank score #defeated #defeated_by details) * "\t"
    hackers_by_rank.each_with_index do |hacker, i|
      puts [i, '%5.2f' % hacker.score, hacker.defeated.length, hacker.defeated_by.length, hacker.inspect] * "\t"
    end
  end
  def random_hackers
    @random_hackers ||= @hackers.sort { rand(2) - 1 }
  end
  # get a pair of hackers that hasn't had a match
  def unmet_pair
    hacker2 = nil
    hacker1 = random_hackers.find do |h1|
      hacker2 = random_hackers.find do |h2|
        (h1 != h2) && !h1.has_met?(h2)
      end
    end
    [hacker1, hacker2]
  end
  # get a two hackers who might or might not be able to beat each other
  def unknowable_pair
    hacker2 = nil
    hacker1 = random_hackers.find do |h1|
      hacker2 = random_hackers.find do |h2|
        (h1 != h2) && !h1.will_defeat?(h2) && !h2.will_defeat?(h1)
      end
    end
    [hacker1, hacker2]
  end
  def matches_are_sane?
    @hackers.each do |h1|
      if h1.defeated.include?(h1) || h1.defeated_by.include?(h1)
        debug h1.inspect + ' has defeated or was defeated by himself (impossible)'
        return false
      end
      (@hackers - [h1]).each do |h2|
        if h1.will_defeat?(h2) && h2.will_defeat?(h1)
          debug h1.inspect +  ' and ' + h2.inspect + ' will defeat each other (impossible)'
          debugger
          return false
        end
      end
    end
    true
  end
end

if $0 == __FILE__
  s = SmartGame.new
  s.educate
  sane = s.matches_are_sane?
  puts 'testing: s.matches_are_sane? = ' + sane.inspect
  raise "insane" unless sane
  s.connect
  s.play
end
