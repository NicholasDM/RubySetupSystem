# Common ruby functions
require 'os'
require 'colorize'
require 'fileutils'
require 'pathname'
require 'open-uri'
require "open3"
require 'digest'
require 'io/console'

# To get all possible colour values print String.colors
#puts String.colors

# Error handling
def onError(errordescription)
  
  puts
  puts ("ERROR: " + errordescription).red
  puts "Stack trace for error: ", caller
  # Uncomment the next line to allow rescuing this
  #raise "onError called!"
  exit 1
end

# Coloured output
def info(message)
  if OS.windows?
    puts message.to_s.colorize(:light_white)
  else
    puts message.to_s.colorize(:light_blue)
  end
end
def success(message)
  if OS.windows?
    puts message.to_s.colorize(:green)
  else
    puts message.to_s.colorize(:light_green)
  end
end
def warning(message)
  if OS.windows?
    puts message.to_s.colorize(:red)
  else
    puts message.to_s.colorize(:light_yellow)
  end
end
def error(message)
  puts message.to_s.colorize(:red)
end

# Waits for a keypress
def waitForKeyPress
  print "Press any key to continue"
  got = STDIN.getch
  # Extra space to overwrite in case next output is short
  print "                         \r"
  
  # Cancel on CTRL-C
  if got == "\x03"
    puts "Got interrupt key, quitting"
    exit 1
  end
end

# Runs command with system (escaped like open3 but can't be stopped if running a long time)
def runSystemSafe(*cmdAndArgs)
  if cmdAndArgs.length < 1
    onError "Empty runSystemSafe command"
  end

  if !File.exists? cmdAndArgs[0] or !Pathname.new(cmdAndArgs[0]).absolute?
    # check that the command exists if it is not a full path to a file
    requireCMD cmdAndArgs[0]
  end

  system(*cmdAndArgs)
  $?.exitstatus
end

# Runs Open3 for the commad, returns exit status
def runOpen3(*cmdAndArgs, errorPrefix: "", redError: false)

  # puts "Open3 debug:", cmdAndArgs

  if cmdAndArgs.length < 1
    onError "Empty runOpen3 command"
  end

  if !File.exists? cmdAndArgs[0] or !Pathname.new(cmdAndArgs[0]).absolute?
    # check that the command exists if it is not a full path to a file
    requireCMD cmdAndArgs[0]
  end

  Open3.popen3(*cmdAndArgs) {|stdin, stdout, stderr, wait_thr|

    # These need to be threads to work nicely on windows
    outThread = Thread.new{
      stdout.each {|line|
        puts line
      }
    }

    errThread = Thread.new{
      stderr.each {|line|
        if redError
          puts (errorPrefix + line).red
        else
          puts errorPrefix + line
        end
      }
    }    

    exit_status = wait_thr.value
    outThread.join
    errThread.join
    return exit_status
  }

  onError "Execution shouldn't reach here"
  
end

# Runs Open3 for the commad, returns exit status and output string
def runOpen3CaptureOutput(*cmdAndArgs)

  output = ""

  if cmdAndArgs.length < 1
    onError "Empty runOpen3 command"
  end

  if !File.exists? cmdAndArgs[0] or !Pathname.new(cmdAndArgs[0]).absolute?
    # check that the command exists if it is not a full path to a file
    requireCMD cmdAndArgs[0]
  end

  Open3.popen3(*cmdAndArgs) {|stdin, stdout, stderr, wait_thr|

    # These need to be threads to work nicely on windows
    outThread = Thread.new{
      stdout.each {|line|
        output.concat(line)
      }
    }

    errThread = Thread.new{
      stderr.each {|line|
        output.concat(line)
      }
    }    

    exit_status = wait_thr.value
    outThread.join
    errThread.join
    return exit_status, output
  }

  onError "Execution shouldn't reach here"
end

# Runs Open3 for the commad, returns exit status. Restarts command a few times if fails to run
def runOpen3StuckPrevention(*cmdAndArgs, errorPrefix: "", redError: false, retryCount: 5,
                            stuckTimeout: 120)

  if cmdAndArgs.length < 1
    onError "Empty runOpen3 command"
  end

  if !File.exists? cmdAndArgs[0] or !Pathname.new(cmdAndArgs[0]).absolute?
    # check that the command exists if it is not a full path to a file
    requireCMD cmdAndArgs[0]
  end

  Open3.popen3(*cmdAndArgs) {|stdin, stdout, stderr, wait_thr|

    lastOutputTime = Time.now

    outThread = Thread.new{
      stdout.each {|line|
        puts line
        lastOutputTime = Time.now
      }
    }

    errThread = Thread.new{
      stderr.each {|line|
        if redError
          puts (errorPrefix + line).red
      else
        puts errorPrefix + line
        end
        lastOutputTime = Time.now
      }
    }

    # Handle timeouts
    while wait_thr.join(10) == nil

      if Time.now - lastOutputTime >= stuckTimeout
        warning "RubySetupSystem stuck prevention: #{Time.now - lastOutputTime} elapsed " +
                "since last output from command"

        if retryCount > 0
          info "Restarting it "
          Process.kill("TERM", wait_thr.pid)

          sleep(5)
          return runOpen3StuckPrevention(*cmdAndArgs, errorPrefix: errorPrefix,
                                         redError: redError, retryCount: retryCount - 1,
                                         stuckTimeout: stuckTimeout)
        else
          warning "Restarts exhausted, going to wait until user interrupts us"
          lastOutputTime = Time.now
        end
      end
    end
    exit_status = wait_thr.value

    outThread.kill
    errThread.kill
    return exit_status
  }

  onError "Execution shouldn't reach here"
  
end

# Runs Open3 with suppressed output
def runOpen3Suppressed(*cmdAndArgs)

  if cmdAndArgs.length < 1
    onError "Empty runOpen3 command"
  end

  requireCMD cmdAndArgs[0]

  Open3.popen2e(*cmdAndArgs) {|stdin, out, wait_thr|

    out.each {|l|}
    
    exit_status = wait_thr.value
    return exit_status
  }

  onError "Execution shouldn't reach here"
  
end

# verifies that runOpen3 succeeded
def runOpen3Checked(*cmdAndArgs, errorPrefix: "", redError: false)

  result = runOpen3(*cmdAndArgs, errorPrefix: errorPrefix, redError: redError)

  if result != 0
    onError "Running command failed (if you try running this manually you need to " +
            "make sure that all the comma separated parts are quoted if they aren't " +
            "whole words): " + cmdAndArgs.join(", ")
  end
  
end

def pathAsArray
  ENV['PATH'].split(File::PATH_SEPARATOR)
end

def pathExtsAsArray
  ENV['PATHEXT'] ? ENV['PATHEXT'].split(';') : ['']
end

# Cross-platform way of finding an executable in the $PATH.
#
#   which('ruby') #=> /usr/bin/ruby
# from: http://stackoverflow.com/questions/2108727/which-in-ruby-checking-if-program-exists-in-path-from-ruby
# Modified to work better for windows
def which(cmd)
  # Could actually rather check that this command with the .exe suffix
  # is somewhere, instead of allowing the suffix to change, but that
  # is probably fine
  if OS.windows?
    if cmd.end_with? ".exe"
      # 5 is length of ".exe"
      cmd = cmd[0..-5]
    end
  end
  
  exts = pathExtsAsArray
  pathAsArray.each do |path|
    exts.each { |ext|
      exe = File.join(path, "#{cmd}#{ext}")
      return exe if File.executable?(exe) && !File.directory?(exe)
    }
  end
  return nil
end


def askRunSudo(*cmd)

  info "About to run '#{cmd.join ' '}' as sudo. Be prepared to type sudo password"
  
  runOpen3Checked(*cmd)
  
end

# Copies file to target folder while preserving symlinks
def copyPreserveSymlinks(sourceFile, targetFolder)

  if File.symlink? sourceFile

    linkData = File.readlink sourceFile

    targetFile = File.join(targetFolder, File.basename(sourceFile))

    if File.symlink? target

      existingLink = File.readlink targetFile

      if linkData == existingLink
        # Already up to date
        return
      end
    end

    FileUtils.ln_sf linkData, targetFile
    
  else

    # Recursive copy should work for normal files and directories
    FileUtils.cp_r sourceFile, targetFolder, preserve: true
    
  end
end


# Downloads an URL to a file if it doesn't exist
# \param hash The hash of the file. Generate by running this in irb:
# `require 'digest'; Digest::SHA2.new(256).hexdigest(File.read("filename"))`
# hashmethod == 1 default hash
# hashmethod == 2 is hash from require 'sha3'
# hashmethod == 3 is sha1 for better compatibility with download sites that only give that
def downloadURLIfTargetIsMissing(url, targetFile, hash, hashmethod = 1, skipcheckifdl = false,
                                 attempts = 5)

  onError "no hash for file dl" if !hash
  
  if File.exists? targetFile

    if skipcheckifdl
      return true
    end
    
    info "Making sure already downloaded file is intact: '#{targetFile}'"
    
  else
    info "Downloading url: '#{url}' to file: '#{targetFile}'"

    begin 
      File.open(targetFile, "wb") do |output|
        # open method from open-uri
        open(url, "rb") do |webDataStream|
          output.write(webDataStream.read)
        end
      end
    rescue
      error "Download failed"
      FileUtils.rm_f targetFile

      if attempts < 1
        raise
      else
        attempts -= 1
        info "Attempting download again, attempts left: #{attempts}"
        return downloadURLIfTargetIsMissing(url, targetFile, hash, hashmethod, skipcheckifdl,
                                            attempts)
      end
    end
    
    onError "failed to write download to file" if !File.exists? targetFile    
  end

  # Check hash
  if hashmethod == 1
    dlHash = Digest::SHA2.new(256).hexdigest(File.read(targetFile))
  elsif hashmethod == 2
    require 'sha3'
    dlHash = SHA3::Digest::SHA256.file(targetFile).hexdigest
  elsif hashmethod == 3
    dlHash = Digest::SHA1.file(targetFile).hexdigest
  else
    raise AssertionError
  end

  if dlHash != hash
    FileUtils.rm_f targetFile

    if attempts < 1
      onError "Downloaded file hash doesn't match expected hash, #{dlHash} != #{hash}"
    else
      attempts -= 1
      error "Downloaded file hash doesn't match expected hash, #{dlHash} != #{hash}"
      info "Attempting download again, attempts left: #{attempts}"
      return downloadURLIfTargetIsMissing(url, targetFile, hash, hashmethod, skipcheckifdl,
                                          attempts)
    end
  end
  
  success "Done downloading"
end

# Makes a windows path mingw friendly path
def makeWindowsPathIntoMinGWPath(path)
  modifiedPath = path.gsub(/\\/, '/')
  modifiedPath.gsub(/^(\w+):[\\\/]/) { "/#{$1.downcase}/" }
end

# Returns current folder as something that can be used to switch directories in mingwg shell
def getMINGWPWDPath()
  makeWindowsPathIntoMinGWPath Dir.pwd
end

# Returns the line endings a file uses
# Will probably return either "\n" or "\r\n"
def getFileLineEndings(file)
  File.open(file, 'rb') do |f|
    return f.readline[/\r?\n$/]
  end
end

# Print data of str in hexadecimal
def printBytes(str)

  puts "String '#{str}' as bytes:"

  str.each_byte { |c|
    puts c.to_s(16) + " : " + c.chr
  }

  puts "end string"
  
end


# Requires that command is found in path. Otherwise shows an error
def requireCMD(cmdName, extraHelp = nil)

  if(cmdName.start_with? "./" or File.exists? cmdName)
    # Skip relative paths
    return
  end

  if which(cmdName) != nil
    # Command found
    return
  end

  # Windows specific checks
  if OS.windows?
    # There are a bunch of inbuilt stuff that aren't files so ignore them here
    case cmdName
    when "call"
      return
    when "start"
      return
    when "mklink"
      return
    end
  end

  # Print current search path
  puts ""
  info "The following paths were searched for " +
       pathExtsAsArray.map{|i| "'#{cmdName}#{i}'"}.join(' or ') + " but it wasn't found:"

  pathAsArray.each{|p|
    puts p
  }
  
  onError "Required program / tool '#{cmdName}' is not installed or missing from path.\n" +
          "Please install it and make sure it is in path, then try again. " +
          "(path is printed above for reference)" + (
            if extraHelp then " " + extraHelp else "" end)  
  
end


# Path helper
# For all tools that need to be in path but shouldn't be installed because of convenience
def runWithModifiedPath(newPathEntries, prependPath=false)
  
  if !newPathEntries.kind_of?(Array)
    newPathEntries = [newPathEntries]
  end
  
  oldPath = ENV["PATH"]

  onError "Failed to get env path" if oldPath == nil

  if OS.windows?
    separator = ";"
  else
    separator = ":"
  end

  if prependPath
    newpath = newPathEntries.join(separator) + separator + oldPath
  else
    newpath = oldPath + separator + newPathEntries.join(separator)
  end

  info "Setting path to: #{newpath}"
  ENV["PATH"] = newpath
  
  begin
    yield
  ensure
    info "Restored old path"
    ENV["PATH"] = oldPath
  end    
end


def getLinuxOS()

  if OS.mac?
    return "mac"
  end
  
  if OS.windows?
    raise "getLinuxOS called on Windows!"
  end

  # Override OS type if wanted
  if $pretendLinux
    return $pretendLinux
  end

  # Pretend to be on fedora to get the package names correctly (as
  # they aren't attempted to be installed this is fine)
  if (defined? "SkipPackageManager") && SkipPackageManager
    return "fedora"
  end

  osrelease = `lsb_release -is`.strip

  onError "Failed to run 'lsb_release'. Make sure you have it installed" if osrelease.empty?

  osrelease.downcase

end


def isInSubdirectory(directory, possiblesub)

  path = Pathname.new(possiblesub)

  if path.fnmatch?(File.join(directory, '**'))
    true
  else
    false
  end
  
end


def createLinkIfDoesntExist(source, linkfile)

  if File.exist? linkfile
    return
  end

  FileUtils.ln_sf source, linkfile
  
end

# Sanitizes path (used by precompiled packager at least)
def sanitizeForPath(str)
  # Code from (modified) http://gavinmiller.io/2016/creating-a-secure-sanitization-function/
  # Bad as defined by wikipedia:
  # https://en.wikipedia.org/wiki/Filename#Reserved_characters_and_words
  badChars = [ '/', '\\', '?', '%', '*', ':', '|', '"', '<', '>', '.', ' ' ]
  badChars.each do |c|
    str.gsub!(c, '_')
  end
  str
end

# Parses symbol definition from breakpad data
# call like `platform, arch, hash, name = getBreakpadSymbolInfo data`
def getBreakpadSymbolInfo(data)
  match = data.match(/MODULE\s(\w+)\s(\w+)\s(\w+)\s(\S+)/)

  if !match || match.captures.length != 4
    raise "invalid breakpad data"
  end

  match.captures
end


# Returns name of 7zip on platform (7za on linux and 7z on windows)
def p7zip
  if OS.windows?
    "7z"
  else
    "7za"
  end
end
