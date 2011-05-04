#!/usr/bin/env ruby
require 'gserver'
require 'rubygems'

@users = [
  ['bkrsta', 'test'],
  ['test', 'test'],
]
@hosting_dir = "/home/bkrsta/samp/hosting"

def logfile() "./telnetsrv.log" end

def parse_input(i)
  if i=='exit' or i=='quit' or i=='q'
    # $stdio.puts "bye! (parse_input)"
    return false
  else
    return i
  end
end


def passw(io)
	io.flush
	x=''
	while x+=io.getc
		io.print "\b"
	end
	x
end

def log_file(msg)
  (log "Greska kod log_file() !"; return false) if msg.nil? or msg.empty?
  log "[LOG] #{msg}"
  File.open(logfile, (File.exists? logfile) ? 'a' : 'w') { |f| f.puts "[#{Time.now}] #{msg}\n" }
end

class Users
  def initialize(db)
    @users = db
  end
  def check(user, pass)
    @users.each do |u|
      if u[0]==user; if u[1]==pass; return true end end
    end
    false
  end
  def log(usr) @in = usr end
  def who() @in || (puts "prazan @in!"; exit) end
end

class MyServer < GServer
  # TODO: koristiti Highline, link: http://bit.ly/9cMIIi
  # TODO: use http://bit.ly/aTRaA3
  def init(db)
    @usage ||= []
    # TODO: ispisi last login u headeru
    @usage << "### cod2man shell ###"
    @usage << " - Za pomoc oko komandi upisi: 'h' ili 'help' ili '?'"
    # @usage << "Last login: Mon Aug  2 18:01:45"
    @usr = Users.new(db)
		@funs = [] # fun, Proc
  end
  def funs
    @funs
  end
  def serve(io)
    loop do
      begin
        log_file "connected: #{io.peeraddr[3]}"
        $stdio = io
        io.puts "Welcome to cod2man telnet server ... !"
        failcnt=0
        loop do # Login screen
          io.puts '-- Please Login'
          io.print 'username: '; username = io.gets.chomp
          io.print 'password: '; password = io.gets.chomp
          if @usr.check(username, password)
            @usr.log username
            io.puts
            io.puts "Successfully logged in as #{@usr.who}!"
            log_file "#{@usr.who} logged in"
            io.puts
            break
          else
            io.puts "Wrong username or password!"
            io.puts
            failcnt+=1
            if failcnt>2
              log_file "User Failed to login #{failcnt} times, killing!"
              io.puts " !! Login failed #{failcnt} times and will be reported to admin !!"
              io.close
            end
          end
        end
        io.puts @usage.join "\n"
        loop do # command prompt
          io.print "cod2man shell $ "
          line_input = parse_input io.gets.chop
          if line_input==false
            log_file "Exit"
            io.puts "bye!"
            io.close
          end
          log_file "Received #{line_input}" if line_input[/./]
          runfun line_input
        end
      rescue Exception => e
        io.puts "Oops - #{e}"
      end
    end
    io.puts ">> GOODBYE <<"
    log_file "Exit"
    io.close
  rescue Exception => e
    puts "#{e}"
  end

	def reg_fun(*args, &block)
		# if name =~ /[a-zA-Z0-9_\-]+/
    name = args
    desc = nil
    if name.last.class == Desc
      desc = name.last.to_s
      name = name[0..name.count-2]
    end
		@funs << [name, desc, block]
	end

	def runfun(inp)
		cmd, args = inp.split(" ", 2)
		args = args.split(" ") rescue []
		@funs.each { |f|
			if f.first.include? cmd
				if f.last.arity>0
					if args.count == f.last.arity
						f.last.call(*args)
					else
						$stdio.puts "Krivi broj argumenata! (treba #{f.last.arity})"
					end
				elsif f.last.arity == -1
					if args.count>0
						f.last.call(*args)
					else
						f.last.call()
					end
				elsif f.last.arity == 0
					if args.count>0
						$stdio.puts "Fun. ne trazi args!"
					else
						f.last.call()
					end
				else
					f.last.call
				end
				return 1
			end
		}
		if inp == ''
			return true
		else
			$stdio.puts "Nepoznata komanda: #{inp}"
		end
	end

end

ts = MyServer.new 1234, "0.0.0.0"
ts.init @users

class Desc
  def initialize(txt)
    @desc = txt
  end
  def to_s
    @desc
  end
end

def D(txt)
  Desc.new(txt)
end

ts.reg_fun("help", "h", "?", D("this message")) {
  l = []
  ts.funs.each {|f|
    cmd = f.first.first
    cot = f.first.count>1 ?
      " (#{f.first[1..f.first.count-1].join ', '})" : nil
    l << ["#{cmd}#{cot}", (f[1].to_s if f[1])]
  }

  maxl = l.collect{|x| x[0].length}.max
  l.each{|f|
    $stdio.printf "%-#{maxl}s", [f.first]
    $stdio.print " - #{f[1]}" if f[1]
    $stdio.print "\n"
  }
}

def parse_ctrl_out(str)
	if str =~ /SAMP Server is not running!!/
		return false
	else
		return true if str[/PID of (.+)/, 1].to_i !=0
	end
	return false
end

ts.reg_fun("status", D("server status")) { |srv|
	if srv =~ /^[a-zA-Z0-9_]+$/
		if File.directory? "#{@hosting_dir}/#{srv}"
			out  = `cd #{@hosting_dir} && ./control #{srv} status`
			pid  = out[/PID of (.+)/, 1].to_i
			ctrl = parse_ctrl_out(out)
			port = `grep port #{@hosting_dir}/#{srv}/server.cfg | sed 's/port //g'`.chop
			out  = port.empty? ? "" : `netstat -a | grep :#{port}\ `
			p    = !out.empty?
			ram  = pid>0 ? `egrep "VmSize|VmRSS" /proc/#{pid}/status` : "FAIL"
			out  = `php /var/www/samp/s.php 127.0.0.1 #{port} | egrep '\^Players'`.empty?

			$stdio.puts "CTRL: #{ctrl ? 'OK' : 'FAIL'}"
			$stdio.puts "PORT: #{p    ? 'OK' : 'FAIL'}"
			$stdio.puts "RCON: #{!out ? 'OK' : 'FAIL'}"
			$stdio.puts "RAM:  \n#{ram}"
		else
			$stdio.puts "ERR: Server '#{srv}' ne postoji!"
		end
	else
		$stdio.puts "ERR!"
	end
}

ts.reg_fun("start", D("start server")) { |srv|
  if srv =~ /^[a-zA-Z0-9_]+$/
    $stido.puts `cd #{@hosting_dir} && ./control #{srv} start`
  end
}

ts.reg_fun("stop", D("stop server")) { |srv|
  if srv =~ /^[a-zA-Z0-9_]+$/
    $stdio.puts `cd #{@hosting_dir} && ./control #{srv} stop`
  end
}

ts.reg_fun("restart", D("restart server")) { |srv|
  if srv =~ /^[a-zA-Z0-9_]+$/
    $stdio.puts `cd #{@hosting_dir} && ./control #{srv} restart`
  end
}

ts.reg_fun("log", D("tail server log")) { |srv|
  if srv =~ /^[a-zA-Z0-9_]+$/
    $stdio.puts `tail #{@hosting_dir}/#{srv}/server_log.txt`
  end
}

ts.reg_fun("status", D("server status, verbose")) {
	$stdio.puts "PRINT STATUS"
}


ts.start
ts.audit = true
ts.join
