# typed: false
# frozen_string_literal: false

# Refactoring software for Erlang language by ELTE and Ericson
class Referl < Formula
  desc "Refactoring software for Erlang language by ELTE and Ericson"
  homepage "https://plc.inf.elte.hu/erlang/index.html"
  #url "https://plc.inf.elte.hu/erlang/dl/refactorerl-0.9.20.08_v2.zip"
  url "http://plc.inf.elte.hu/erlang/dl/RefactorErl_trunk.zip"
  version "0.9.20.08"
  #sha256 "52f0778c42f7c48490f93b07a435cb3f8c3573810765b6255145e6972edc0cea"
  sha256 "8a1bd8b17e872457027203cd256cdb03628b9589d0e6d922027e29566cb78c3b"
  license "LGPL-3.0-only" # SPDX Representation for: GNU Lesser General Public License v3.0 only

  depends_on "erlang"
  depends_on "gcc" 
  depends_on "graphviz" 
  depends_on "yaws"

  bottle :unneeded

  # Creating exec script
  def create_exec_script
    out_file = File.new("bin/referl_exec", "w")
    out_file.puts("#\!\/bin\/bash")
    out_file.puts("#{String.new(HOMEBREW_PREFIX)}/Cellar/referl/#{version}/bin/referl_boot -base #{String.new(HOMEBREW_PREFIX)}/Cellar/referl/#{version}/ $@")
    out_file.close
  end

  def yaws_detect
    yaws_version = `yaws --version`.split[-1]
    yaws_path = "#{String.new(HOMEBREW_PREFIX)}/Cellar/yaws/#{yaws_version}/lib/yaws-#{yaws_version}/ebin"
    ohai "Looking for YAWS path on: #{yaws_path}"
    if File.directory?(yaws_path)
      ohai "Yaws found!"
    else
      odie("Error! - yaws path not found, you may need to install one manually")
    end
    yaws_path
  end

  def installpaths
    install_paths = []
    Dir["bin/*"].each { |x| install_paths.push(String.new(x)) }
    install_paths.delete("bin/referl")
    install_paths.delete("bin/referl_exec")
    install_paths
  end

  def instal_referl
    install_paths = installpaths

    # Installing
    bin.install install_paths
    bin.install "bin/referl" => "referl_boot" # Rename referl to avoid conflicts with symlink
    lib.install Dir["lib/*"]
    prefix.install "refactorerl.boot"
    prefix.install "sys.config"

    bin.install "bin/referl_exec" => "referl" # Symlink will be pointed to this script, due to rename
  end

  def install
    yaws_path = yaws_detect
    create_exec_script

    system "bin/referl", "-build", "tool", "-yaws_path", yaws_path
    instal_referl
  end


  def test_referl_badarg
    puts "=== Test Case: Bad Arg ======================================"
    pid = fork do
      exec "referl -badarg"
    end
    sleep 1
    begin
      Process.getpgid(pid)
      return true 
    rescue Errno::ESRCH
      return false
    end
  end

  def test_referl_start
    kill_pid = 0
    begin
      pid = fork do #todo rename
        system "referl -name test@localhost"
      end
      kill_pid = Process.pid
      puts "=== Test Case: No  Arg ======================================"
      puts "Forked pid: #{pid}"
      sleep 1

      # CHECK IF THE PARENT PROCESS EVEN ALIVE
      begin
        Process.getpgid(pid)
      rescue Errno::ESRCH
        return false
      end

      all_pids = `pgrep -f "bin/referl"`.split("\n")
      puts "Process found with 'referl': #{all_pids.length}"
      exec_script_pid = `pgrep -f "referl_boot"`.split("\n")[0]
      all_pids.delete(exec_script_pid)
      puts "Process found with 'referl' –exec_script_pid: #{all_pids.length}"


      possible_pids = []
      if all_pids.length == 0
        puts "No referl instance found!"
        return false

      elsif all_pids.length == 1
        command = "ps -o ppid= -p #{all_pids[0]}"
        parent_of = Integer(shell_output(command))
        puts "Exactly one referl instance found: #{all_pids[0]} => Parent is: #{parent_of}" 
        if parent_of == pid
          puts "PID is ok."
          possible_pids.push(all_pids[0])
        elsif
          puts "The found referl instance was not started by process: #{pid}"
        end

      elsif all_pids.length > 1
        puts "Multiple referl instance found"
        all_pids.each do |x|
          command = "ps -o ppid= -p #{x}"
          parent_of = Integer(shell_output(command))
          puts "Current pid: #{x} => Parent is: #{parent_of}"
          if Integer(parent_of) == pid
            puts "PID is ok."
            possible_pids.push(x)
          end
        end
      end


      if possible_pids.length == 1 
        begin
          Process.getpgid(Integer(possible_pids[0]))
          puts "Found referl pid: #{possible_pids[0]} is alive."
          return true 
        rescue Errno::ESRCH
          puts "Found referl pid: #{possible_pids[0]} is NOT alive."
          return false
      end
      elsif possible_pids.length == 0
        puts "No referl instance passed the previous validation process. (parental issues)"
        return false
      else
        puts "Multiple referl process were assosiated with this process, which shoudl not happen."
      end

      #system "kill", "ps -o pid= --ppid $$"

    ensure
      system "kill", "ps -o pid= --ppid #{pid}"
      #pids_kill = shell_output("ps -o pid= --ppid $$")
      #system "kill", "ps -o pid= --ppid $$"
    end

  end

  test do
    # Test Case #1 – Starting referl with bad arguments => should fail
    assert_equal(false, test_referl_badarg)

    #! - ... used by another Erlang node-ra is megfelel... (Docker?/Izolált környezet)
    #! - MNESIA nem szereti az -sname-et
    # Test Case #2 – Starting referl with no arguments
    assert_equal(true, test_referl_start)

    # Test Case #3 - referl -name erlang@elte

    # Test Case #4 - referl -name -erlang

    # Test Case #5 – Starting referl with: -db kcmini
    #! Itt se nagyon fogunk tudni teszteli, ha nem -sname-elünk, de legalább ez szereti
    # referl -db kcmini -sname robi

    # Test Case #6 – Testing with YAWS
    #! Itt is used by another erlang node léphet fel...
    


# Todo yaws csak így:
# ri:start_web2([{yaws_path, "/usr/local/Cellar/yaws/2.0.9/lib/yaws-2.0.9/ebin"}]).
# cmd-ból sem

    






   

    # puts yaws_detect
    # puts "Parent arent: #{Process.pid}"
    # pid = fork do
    #   exec "referl"
    # end
    # begin
    #   puts Process.getpgid(10)
    # rescue 
    #   puts "No proc!"
    # end

    # begin
    #   puts Process.getpgid(pid)
    # rescue 
    #   puts "No proc!"
    # end


   
    # puts "Child: #{pid}"
    # puts pids

    # sleep 5

  

    
    ohai "ALL TESTS ARE PASSED."
    
  
  end
end
