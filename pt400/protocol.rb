# for 2010 defcon quals (18) by cvk
# 6af3db1bb81f2d056d3ae59d61c589bb

require 'socket'
require 'digest/sha1'

HOST = ARGV.shift || 'game.ddtek.biz'
PORT = ARGV.shift || 8129
GAMELOG = 'gamelog'

class Game
  def read_int
    @sock.read(4).unpack('N')[0]
  end
  def read(bytes_to_read)
    @sock.read(bytes_to_read)
  end
  def decode_length(int)
    int ^ 0xc932f768
  end
  def decode(data)
    decoder_byte = data.length & 255
    (0...data.length).each do |j|
      data[j] = data[j] ^ decoder_byte
    end
    data
  end
  def checksum(data)
    Digest::SHA1.hexdigest(data)
  end
  # write image to disk for user to see
  #
  # checksums image file and returns checksum as hacker id
  def save_image(data)
    hacker_id = checksum(data)
    File.open(checksum(data) + '.jpg', 'w') do |f|
      f.write data
      debug 'wrote %d bytes to %s' % [data.length, f.path]
    end
    hacker_id
  end
  def debug(text)
    puts text if true
  end
  # reads an image and stores it
  #
  # if the protocol returns an error value, it is raised
  def receive_image
    bytes_to_read = decode_length(read_int)
    bytes_to_read -= 2**32 if bytes_to_read > 2**31 # unsigned to signed
    raise ProtocolException.new(bytes_to_read) if bytes_to_read < 0
    data = read(bytes_to_read)
    save_image(decode(data))
  end
  def get_new_hackers
    if @last_move
      debug 'checking on last guess and getting new hackers'
    else
      debug 'getting new hackers'
    end
    @hacker_id1, @hacker_id2 = receive_image, receive_image
  end
  def play
    loop do
      get_new_hackers
      move
      loop do
        begin
          status
          get_new_hackers
          
          # if get_hackers didn't raise an exception, we know our last move was
          # correct
          good_guess
          learn_from_last_move :correct

          move
        rescue ProtocolException => p
          # game over (could be good or bad)
          case p.value
          when -1, -2
            bad_guess
            learn_from_last_move :incorrect
            @last_move = nil
            reconnect
            break
          when -3
            print 'what sequence? >'
            sequence = gets.chomp
            @sock.write sequence
          when -4
            puts @sock.read(10000).inspect
          end
        end
      end
    end
  end
  def status; end # to be overridden
  def good_guess
    debug 'last guess was good'
  end
  def bad_guess
    debug 'last guess was bad'
  end
  def learn_from_last_move(status)
    chosen = @last_move[:chosen]
    not_chosen = @last_move[:not_chosen]
    @matches <<
      if status == :correct
        {:winner => chosen, :loser => not_chosen}
      else
        {:winner => not_chosen, :loser => chosen}
      end
    debug 'i learned a new match: ' + @matches.last.inspect
    log @matches.last
  end
  # records win/loss stats in a file for learning purposes
  def log(match)
    @log.puts match[:winner] + ' beat ' + match[:loser]
  end
  # always goes for hacker1
  def move
    debug 'guessing hacker1'
    @sock.write "\000"
    @last_move = {:chosen => @hacker_id1, :not_chosen => @hacker_id2}
  end
  def connect
    @sock = TCPSocket.new(HOST, PORT)
    @sock.write "illogical\n"
  end
  def reconnect
    @sock.close
    connect
  end
  def initialize
    @matches = []
    @log = File.open(GAMELOG, 'a')
    @last_move = nil
    @log.sync = true
  end
end

class ProtocolException < Exception
  attr_reader :value
  def initialize(value)
    @value = value
  end
end

if $0 == __FILE__
  g = Game.new
  g.connect
  g.play
end
