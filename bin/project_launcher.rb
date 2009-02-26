# Project Launcher (OSX)

# A simple, small ruby script to launch commands on a single multi-tabbed OSX Terminal.
# Project configuration is set in projects.yml, where detection (based on folder precedence) 
# and terminal commands can be setup.  See README for information on installation/usage and 
# setting up. For anything else check the latest commit logs.

# example projects.yml shows commands for a Ruby on Rails project with textmate,git,rspec,autotest,mongrel 
# (and growlnotify installed) - also a basic erlang project, and a useless default

# Author:       Matthew Hutchinson
# URL:          http://matthewhutchinson.net
# Requirements: > Ruby 1.8.6, rb-appscript gem, sense of humor
# Credits:      inspired by Solomon White - http://onrails.org/articles/2007/11/28/scripting-the-leopard-terminal 

require 'find'
require 'rubygems'
require 'yaml'
require 'appscript'
include Appscript


class ProjectLauncher
  
  @@terminal        = app('Terminal')
  @@config          = YAML::load(File.open( File.join(File.dirname(__FILE__), 'config.yml') ))
  @@projects_folder = @@config.delete('projects_folder')
  @@search_depth    = @@config.delete('search_depth')
  @@default_profile = @@config.delete('default')

  def initialize(project_name)

    @window   = nil
    needs_pwd = true
    
    # operate no working dir if no project name
    if project_name == nil
      project_name = Dir.pwd.split('/').last
      matches      = find_project(project_name)
    else
      matches   = find_project(project_name, File.expand_path(@@projects_folder))
      needs_pwd = false
    end

    case matches.length
      when 0
        puts "Launch Robot: Sorry, I couldn't find any project matching '#{project_name}'"
        exit
      when 1
        # modified to always pick first match
        @project_folder = needs_pwd ? File.join(matches.first) : matches.first
      else
        # TODO : pick one?
        @project_folder = needs_pwd ? File.join(matches.first) : matches.first
        puts "Launch Robot: I found a few matches for '#{project_name}':\n\n  #{matches.join("\n  ")}\n\nLaunch Robot: I just went ahead and picked the first one for you"
    end

    detect_project_type
  end

  def find_project(name_fragment, root_folder = nil)
    matches = []
    Find.find(root_folder ||= Dir.pwd) do |path|
      # limit to search depth
      partial_path = path.gsub(root_folder, '')
      Find.prune if partial_path =~ /^\./
      depth = partial_path.split('/').length
      Find.prune if depth > @@search_depth + 1

      # look for directory matching name fragment
      if FileTest.directory?(path)
        if path =~ /#{name_fragment}/i
          matches << path
          Find.prune
        end
      end

      next
    end
    matches
  end

  def detect_project_type
    folders, files = Dir["#{@project_folder}/*"].map{|f| File.basename(f) }.partition{|f| FileTest.directory?("#{@project_folder}/#{f}") }
    @profile = @@config['projects'].find do |name, config|
      if name == "default"
        true
      else
        case config['detection']
        when nil, "true"
          true
        when Hash
          ((! config['detection'].has_key? 'folders') ||
          config['detection']['folders'].all? {|f| folders.include?(f) }) &&
          ((! config['detection'].has_key? 'files') ||
          config['detection']['files'].all? {|f| files.include?(f) })
        end
      end
    end

    if @profile
      @profile = @profile[1]
    else
      @profile = @@default_profile
    end

    unless @profile
      puts "Launch Robot: Sorry, I could not find a matching profile for that project"
      exit
    end

    # changed to be silent on success
    puts "Launch Robot: Launching in #{@project_folder} ..."
  end

  def launch
    @profile['tasks'].each do |tab|
      run tab
    end
  end

  def run(action)
    @window && new_tab(action) || new_window(action)
  end

  def new_window(action)
    @first_tab = @@terminal.do_script(build_project_command(action))
    @window = eval @first_tab.to_s.gsub(/\.tabs.*$/, '') # bit of a nasty hack here
  end

  def new_tab(action)
    @window.frontmost.set(true)
    app("System Events").application_processes["Terminal.app"].keystroke("t", :using => :command_down)
    while (@window.tabs.last.busy.get)
      # wait for new tab
      sleep 2
    end
    @@terminal.activate
    @@terminal.do_script(build_project_command(action), :in => @window.tabs.last.get)
  end

  def build_project_command(action)
    detected_project_name = @project_folder.split('/').last
    parsed_command = action['command'].gsub('{project_name}', detected_project_name) if action['command']
    ["cd #{@project_folder}",
    "echo -n -e \"\\033]0;#{action['label']}\\007\"",
    "clear",
    parsed_command || 'clear'].join(';')
  end
end


ProjectLauncher.new(ARGV.shift).launch if __FILE__ == $0