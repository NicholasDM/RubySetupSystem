# Installer class
require 'etc'

## Install runner
class Installer
  # basedepstoinstall Is an array of BaseDep derived objects that install
  # the required libraries
  def initialize(basedepstoinstall)

    @Libraries = basedepstoinstall

    if not @Libraries.kind_of?(Array)
      onError("Installer passed something else than an array")
    end

    @SelfLib = nil
  end

  # Adds an extra library
  def addLibrary(lib)

    @Libraries.push lib
  end

  # If the main project being built is available as a RubySetupSystem
  # library it can be added here to install its dependencies
  def registerSelfAsLibrary(selflib)

    @SelfLib = selflib
  end

  def doPrerequisiteInstalls(lib)
    # Verifying that it works
    begin
      # Require that this list method exists
      deps = lib.depsList
    rescue RuntimeError
      # Not used on platform. Should always be used on non-windows
      if !OS.windows?
        onError "Dependency #{lib.Name} prerequisites fetch failed. This needs to " + 
                "work on non-windows platforms"
      end
      
      return
    end
    
    onError "empty deps" if !deps
    
    if !DoSudoInstalls or SkipPackageManager

      warning "Automatic dependency installation is disabled!: please install: " +
              "'#{deps.join(' ')}' manually for #{lib.Name}"
    else
      
      # Actually install
      info "Installing prerequisites for #{lib.Name}..."
      
      lib.installPrerequisites
      
      success "Prerequisites installed."
      
    end    
  end

  # Returns true if lib is enabled (ie. not disabled)
  def libEnabled(lib)

    # Disable check
    if NoSpecificDeps
      NoSpecificDeps.each{|selected|

        if selected.casecmp(lib.Name).zero? || selected.casecmp(lib.FolderName).zero?
          info "Dependency #{lib.Name} was specified to be skipped"
          return false
        end
      }
    end

    if !OnlySpecificDeps
      true
    else

      OnlySpecificDeps.each{|selected|

        if selected.casecmp(lib.Name).zero? || selected.casecmp(lib.FolderName).zero?
          return true
        end
      }

      info "Dependency #{lib.Name} is not selected to be setup"
      false
    end
  end

  # Runs the whole thing
  # calls onError if fails
  def run

    success "Starting RubySetupSystem run."

    enabledLibs = @Libraries.select{|i| libEnabled i}

    if not OnlyMainProject and
      enabledLibs.each do |x|

        if x.respond_to?(:installPrerequisites)
          
          self.doPrerequisiteInstalls x
        end
      end
    end

    # Determine what can be precompiled
    precompiled = {}

    enabledLibs.each do |x|

      pre = getSupportedPrecompiledPackage x

      if pre
        precompiled[x.Name] = pre
      end
    end

    info "Using #{precompiled.length} precompiled libraries"

    if not SkipPullUpdates and not OnlyMainProject
      puts ""
      info "Retrieving dependencies"
      puts ""
      
      enabledLibs.each do |x|

        # Precompiled is handled later
        if precompiled.include? x.Name
          next
        end
        
        x.Retrieve
        
      end

      puts ""
      success "Successfully retrieved all dependencies. Beginning compile"
      puts ""
    else

      if SkipPullUpdates
        warning "Not updating dependencies. This may or may not work"
      end

      # Make sure the folders exist, at least
      enabledLibs.each do |x|

        # Precompiled is handled later
        if precompiled.include? x.Name
          next
        end

        if x.RequiresClone
          info "Dependency is missing, downloading it despite update pulling is disabled"
          x.Retrieve
        elsif x.IsUsingSpecificCommit
          info "Making sure dependency '#{x.Name}' has right commit even though " +
               "pull updates is disabled"
          x.MakeSureRightCommitIsCheckedOut
        end
      end      
    end

    if !precompiled.empty?

      puts ""
      info "Retrieving precompiled dependencies"
      puts ""

      precompiled.each{|key, p|
        p.retrieve
      }
      
      puts ""
      success "Successfully retrieved precompiled"
      puts ""
    end
    
    if not OnlyMainProject

      info "Configuring and building dependencies"

      enabledLibs.each do |x|

        if precompiled.include? x.Name

          puts "Extracting precompiled dependency #{x.Name}"
          precompiled[x.Name].install
          
        else
          x.Setup
          x.Compile
          x.Install          
        end

        if x.respond_to?(:Enable)
          x.Enable
        end
        
        puts ""
        
      end

      puts ""
      success "Dependencies done, configuring main project"
    end

    puts ""
    
    if OnlyDependencies

      success "All done. Skipping main project"
      exit 0
    end

    if $options.include?(:projectFullParallel)
      if $options.include?(:projectFullParallelLimit)
        $compileThreads = [Etc.nprocessors, $options[:projectFullParallelLimit]].min
      else
        $compileThreads = Etc.nprocessors
      end
      
      info "Using fully parallel build for main project, threads: #{$compileThreads}"
    end

    # Install project dependencies
    if @SelfLib
      self.doPrerequisiteInstalls @SelfLib
    end

    # Make sure dependencies are enabled even if they aren't built this run
    @Libraries.each do |x|

      if x.respond_to?(:Enable)
        x.Enable
      end
    end
    
  end
  
end
