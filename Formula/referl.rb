# typed: false
# frozen_string_literal: false

# Refactoring software for Erlang language by ELTE and Ericson
class Referl < Formula
  desc "Refactoring software for Erlang language by ELTE and Ericson"
  homepage "https://plc.inf.elte.hu/erlang/index.html"
  # url "https://plc.inf.elte.hu/erlang/dl/refactorerl-0.9.20.08_v2.zip"
  url "https://plc.inf.elte.hu/erlang/dl/RefactorErl_trunk.zip"
  version "0.9.20.08"
  # sha256 "52f0778c42f7c48490f93b07a435cb3f8c3573810765b6255145e6972edc0cea"
  sha256 "8a1bd8b17e872457027203cd256cdb03628b9589d0e6d922027e29566cb78c3b"
  license "LGPL-3.0-only" # SPDX Representation for: GNU Lesser General Public License v3.0 only

  bottle :unneeded

  depends_on "erlang"
  depends_on "gcc"
  depends_on "graphviz"
  depends_on "yaws"

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
    install_paths.delete("bin/referl.bat")
    install_paths
  end

  def libpaths
    lib_paths = []
    Dir["lib/*"].each { |x| lib_paths.push(String.new(x)) }
    lib_paths.delete("lib/build.rules")
    lib_paths
  end

  def instal_referl
    bin.install installpaths
    bin.install "bin/referl" => "referl_boot" # Rename referl to avoid conflicts with symlink
    lib.install libpaths
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

  def check_and_del_data
    if File.directory? "data"
      if `ls data`.include? "refactorerl.configuration_mnesia"
        `rm -r data`
      end
    end
    #! TODO: Ez így rm?
  end

  def kill_erts(exec_script_pid)
    erts_pids = `pgrep -f "erlang/erts"`.split("\n")
    erts_pids.each do |p|
      parent_of = Integer(`ps -o ppid= -p #{p}`)
      puts "CHECK ERTS pid: #{p}, which is child of: #{parent_of} || exec pid: #{exec_script_pid}"
      if Integer(parent_of) == Integer(exec_script_pid)
        puts "Killing ERTS pid: #{p}, which is child of: #{parent_of} (exec script)"
        system "kill", p
      end
    end
  end

  def test_referl_with_params(params, name)
    puts "=== Test Case: #{name} ====================================="
    check_and_del_data
    pid = fork do
      system "referl", params
    end
    puts "Forked pid: #{pid}"
    sleep 1 # TODO: Must??

    # CHECK IF THE PARENT PROCESS EVEN ALIVE
    begin
      Process.getpgid(pid)
    rescue Errno::ESRCH
      puts "No pid!"
      false
    end

    all_pids = `pgrep -f "bin/referl"`.split("\n")
    exec_script_pid = `pgrep -f "referl_boot"`.split("\n")[0]
    all_pids.delete(exec_script_pid)

    possible_pids = []
    if all_pids.empty?
      puts "No referl instance found!"
      return false

    elsif all_pids.length == 1
      parent_of = Integer(`ps -o ppid= -p #{all_pids[0]}`)
      puts "Exactly one referl instance found: #{all_pids[0]} => Parent is: #{parent_of}"
      if parent_of == pid
        puts "PID is ok."
        possible_pids.push(all_pids[0])
      else
        puts "The found referl instance was not started by process: #{pid}"
      end

    elsif all_pids.length > 1
      puts "Multiple referl instance found"
      all_pids.each do |x|
        parent_of = Integer(`ps -o ppid= -p #{all_pids[0]}`)
        puts "Current pid: #{x} => Parent is: #{parent_of}"
        if Integer(parent_of) == pid
          puts "PID is ok."
          possible_pids.push(x)
        end
      end
    end

    success = false
    if possible_pids.length == 1
      begin
        Process.getpgid(Integer(possible_pids[0]))
        puts "Found referl pid: #{possible_pids[0]} is alive."
        success = true
      rescue Errno::ESRCH
        puts "Found referl pid: #{possible_pids[0]} is NOT alive."
      end
    else
      puts "No/Multiple referl proc. were found with this proc. Count: #{possible_pids.length}"
    end

    sleep 1  # TODO: MUST -> wait for the other erts pids to finish?? maybe
    kill_erts exec_script_pid
    Process.waitpid(pid, 0)
    
    success
  end

  def test_referl_with_yaws
    puts "=== Test Case: YAWS ====================================="
    if ! `curl --silent localhost:8001`.include? "<title>RefactorErl</title>"
      puts "Yaws is not running on localhost:8001, with RefactorErl"
    end

    check_and_del_data
    yaws_path = yaws_detect
    pid = fork do
      system "referl", "-yaws_path", yaws_path, "-web2"
    end
    puts "Forked pid: #{pid}"
    sleep 1 # TODO: Must

    # CHECK IF THE PARENT PROCESS EVEN ALIVE
    begin
      Process.getpgid(pid)
    rescue Errno::ESRCH
      puts "No pid!"
      false
    end


    all_pids = `pgrep -f "bin/referl"`.split("\n")
    exec_script_pid = `pgrep -f "referl_boot"`.split("\n")[0]
    all_pids.delete(exec_script_pid)

    possible_pids = []
    if all_pids.empty?
      puts "No referl instance found!"
      return false

    elsif all_pids.length == 1
      parent_of = Integer(`ps -o ppid= -p #{all_pids[0]}`)
      puts "Exactly one referl instance found: #{all_pids[0]} => Parent is: #{parent_of}"
      if parent_of == pid
        puts "PID is ok."
        possible_pids.push(all_pids[0])
      else
        puts "The found referl instance was not started by process: #{pid}"
      end

    elsif all_pids.length > 1
      puts "Multiple referl instance found"
      all_pids.each do |x|
        parent_of = Integer(`ps -o ppid= -p #{all_pids[0]}`)
        puts "Current pid: #{x} => Parent is: #{parent_of}"
        if Integer(parent_of) == pid
          puts "PID is ok."
          possible_pids.push(x)
        end
      end
    end
    
    success = false
    if possible_pids.length == 1
      begin
        Process.getpgid(Integer(possible_pids[0]))
        puts "Found referl pid: #{possible_pids[0]} is alive."
        success = true
      rescue Errno::ESRCH
        puts "Found referl pid: #{possible_pids[0]} is NOT alive."
      end
    else
      puts "No/Multiple referl proc. were found with this proc. Count: #{possible_pids.length}"
    end

    sleep 3 # TODO: It is must, to give time to YAWS to stand
    if ! (`curl --silent localhost:8001`.include? "<title>RefactorErl</title>")
      puts "That it is not our YAWS."
      success = false
    end
    
    sleep 1 # TODO: MUST ???
    kill_erts exec_script_pid
    Process.waitpid(pid, 0)
    
    success
  end


  test do
    # Test Case #1 - Starting referl with bad arguments => should fail
    assert_equal(false, test_referl_with_params("-badparam", "Bad Parameter"))

    # Test Case #2 - Starting referl with no arguments
    assert_equal(true, test_referl_with_params("", "NO ARGS"))

    # Test Case #3 - Starting referl with only -name test@localhost arguments
    assert_equal(true, test_referl_with_params("-name test@localhost", "-NAME"))

    # Test Case #4 - Starting referl with: -db kcmini and -sname
    assert_equal(true, test_referl_with_params("-db kcmini -sname elte", "KCMINI & SNAME"))

    # Test Case #5 - Testing with YAWS
    assert_equal(true, test_referl_with_yaws)

    # ? Észrevételek
    # Todo yaws csak igy:
    # ri:start_web2([{yaws_path, "/usr/local/Cellar/yaws/2.0.9/lib/yaws-2.0.9/ebin"}]).
    # CMD-ben is meg kell adni a yawspath-ot. akkor miért adom meg telepítésnél?

    # git push https://github.com/robertfiko/homebrew-core/ referl


    ohai " ✅ ALL TESTS ARE PASSED. ✅"
  end
end
