# coding: utf-8
# A ruby script for downloading and installing C++ project dependencies
# Made by Henri Hyyryläinen

require_relative 'RubyCommon.rb'
require_relative 'DepGlobber.rb'

require 'optparse'
require 'fileutils'
require 'etc'
require 'os'
require 'open3'
require 'pathname'
require 'zip'

## Used by: verifyVSProjectRuntimeLibrary
#require 'nokogiri' if OS.windows?
## Required for installs on windows
##require 'win32ole' if OS.windows?


#
# Parse options
#

options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: Setup.rb [OPTIONS]"

  opts.on("--[no-]sudo", "Run commands that need sudo. " +
                         "This may be needed to run successfuly") do |b|
    options[:sudo] = b
  end 
  opts.on("--only-project", "Skip all dependencies setup") do |b|
    options[:onlyProject] = true
  end

  opts.on("--only-deps", "Skip the main project setup") do |b|
    options[:onlyDeps] = true
  end

  opts.on("-h", "--help", "Show this message") do
    puts opts
    if defined? extraHelp
      puts extraHelp
    end
    exit
  end
  
end.parse!

if !ARGV.empty?
  # Let application specific args to be parsed
  if defined? parseExtraArgs
    parseExtraArgs
  end

  if !ARGV.empty?

    onError("Unkown arguments. See --help. This was left unparsed: " + ARGV.join(' '))

  end
end

### Setup variables
CMakeBuildType = "RelWithDebInfo"
CompileThreads = Etc.nprocessors

# If set to false won't install libs that need sudo
DoSudoInstalls = if options.include?(:sudo) then options[:sudo] else true end

# If true dependencies won't be updated from remote repositories
SkipPullUpdates = false

# If true skips all dependencies
OnlyMainProject = if options[:onlyProject] then true else false end

# If true skips the main project
OnlyDependencies = if options[:onlyDeps] then true else false end

# If true new version of depot tools and breakpad won't be fetched on install
NoBreakpadUpdateOnWindows = false

# On windows visual studio will be automatically opened if required
AutoOpenVS = true

# Visual studio version on windows, required for forced 64 bit builds
VSVersion = "Visual Studio 14 2015 Win64"
VSToolsEnv = "VS140COMNTOOLS"

# TODO create a variable for running the package manager on linux if possible

### Commandline handling
# TODO: add this

if OS.linux?
  HasDNF = which("dnf") != nil
else
  HasDNF = false
end

# This verifies that CurrentDir is good and assigns it to CurrentDir
CurrentDir = checkRunFolder Dir.pwd

ProjectDir = projectFolder CurrentDir

#
# Initial options / status print
#

info "Running in dir '#{CurrentDir}'"
puts "Project dir is '#{ProjectDir}'"

if HasDNF
  info "Using dnf package manager"
end

puts "Using #{CompileThreads} threads to compile, configuration: #{CMakeBuildType}"

require_relative "Installer.rb"
require_relative "RubyCommon.rb"
require_relative "WindowsHelpers.rb"
require_relative 'CustomInstaller.rb'

# Returns true if sudo should be enabled
def shouldUseSudo(localOption, warnIfMismatch = true)

  if localOption

    if !DoSudoInstalls

      if warnIfMismatch

         warning "Sudo is globally disabled, but a command should be ran as sudo.\n" +
                 "If something breaks please rerun with sudo allowed."
      end

      return false
      
    end

    return true
    
  end

  return false
end

# Returns "sudo" or "" based on options
def getSudoCommand(localOption, warnIfMismatch = true)

  if(!shouldUseSudo localOption, warnIfMismatch)
    return ""
  end
  
  return "sudo "
end

require_relative "LibraryCopy.rb"

require_relative "Dependency.rb"

# Library installs are now in separate files in the Libraries sub directory


