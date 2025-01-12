require 'yaml'
require 'fileutils'
require './tools/unity/auto/unity_test_summary'
require './tools/unity/auto/generate_test_runner'
require './tools/unity/auto/colour_reporter'

module RakefileHelpers

  C_EXTENSION = '.c'
  
  def load_configuration(config_file)
    $cfg_file = config_file
    $cfg = YAML.load(File.read($cfg_file))
    $colour_output = false unless $cfg['colour']
  end
  
  def configure_clean
    CLEAN.include($cfg['compiler']['build_path'] + '*.*') unless $cfg['compiler']['build_path'].nil?
  end
  
  def configure_toolchain(config_file=DEFAULT_CONFIG_FILE)
    config_file += '.yml' unless config_file =~ /\.yml$/
    load_configuration(config_file)
    configure_clean
  end
  
  def get_unit_test_files
    path = $cfg['compiler']['unit_tests_path'] + '**/test_*' + C_EXTENSION
    path.gsub!(/\\/, '/')
    FileList.new(path)
  end
  
  def get_local_include_dirs
    include_dirs = $cfg['compiler']['includes']['items'].dup
    include_dirs.delete_if {|dir| dir.is_a?(Array)}
    return include_dirs
  end

  def extract_headers(filename)
    includes = []
    lines = File.readlines(filename)
    lines.each do |line|
      m = line.match(/^\s*#include\s+\"\s*(.+\.[hH])\s*\"/)
      if not m.nil?
        includes << m[1]
      end
    end
    return includes
  end

  def find_source_file(header, paths)
    paths.each do |dir|
      src_file = dir + header.ext(C_EXTENSION)
      if (File.exists?(src_file))
        return src_file
      end
    end
    return nil
  end
  
  def tackit(strings)
    case(strings)
      when Array
        "\"#{strings.join}\""
      when /^-/
        strings
      when /\s/
        "\"#{strings}\""
      else
        strings
    end
  end
  
  def squash(prefix, items)
    result = ''
    items.each { |item| result += " #{prefix}#{tackit(item)}" }
    return result
  end

  def build_compiler_fields
    command  = tackit($cfg['compiler']['path'])
    if $cfg['compiler']['defines']['items'].nil?
      defines  = ''
    else
      defines  = squash($cfg['compiler']['defines']['prefix'], $cfg['compiler']['defines']['items'])
    end
    options  = squash('', $cfg['compiler']['options'])
    includes = squash($cfg['compiler']['includes']['prefix'], $cfg['compiler']['includes']['items'])
    includes = includes.gsub(/\\ /, ' ').gsub(/\\\"/, '"').gsub(/\\$/, '') # Remove trailing slashes (for IAR)
    return {:command => command, :defines => defines, :options => options, :includes => includes}
  end

  def compile(file, defines=[])
    compiler = build_compiler_fields
    cmd_str = "#{compiler[:command]}#{compiler[:defines]}#{compiler[:options]}#{compiler[:includes]} #{file} " +
      "#{$cfg['compiler']['object_files']['prefix']}#{$cfg['compiler']['object_files']['destination']}" +
      "#{File.basename(file, C_EXTENSION)}#{$cfg['compiler']['object_files']['extension']}"
    execute(cmd_str)
  end
  
  def build_linker_fields
    command  = tackit($cfg['linker']['path'])
    if $cfg['linker']['options'].nil?
      options  = ''
    else
      options  = squash('', $cfg['linker']['options'])
    end
    if ($cfg['linker']['includes'].nil? || $cfg['linker']['includes']['items'].nil?)
      includes = ''
    else
      includes = squash($cfg['linker']['includes']['prefix'], $cfg['linker']['includes']['items'])
    end
    includes = includes.gsub(/\\ /, ' ').gsub(/\\\"/, '"').gsub(/\\$/, '') # Remove trailing slashes (for IAR)
    return {:command => command, :options => options, :includes => includes}
  end
  
  def link(exe_name, obj_list)
    linker = build_linker_fields
    cmd_str = "#{linker[:command]}#{linker[:options]}#{linker[:includes]} " +
      (obj_list.map{|obj|"#{$cfg['linker']['object_files']['path']}#{obj} "}).join +
      $cfg['linker']['bin_files']['prefix'] + ' ' +
      $cfg['linker']['bin_files']['destination'] +
      exe_name + $cfg['linker']['bin_files']['extension']
    execute(cmd_str)
  end
  
  def build_simulator_fields
    return nil if $cfg['simulator'].nil?
    if $cfg['simulator']['path'].nil?
      command = ''
    else
      command = (tackit($cfg['simulator']['path']) + ' ')
    end
    if $cfg['simulator']['pre_support'].nil?
      pre_support = ''
    else
      pre_support = squash('', $cfg['simulator']['pre_support'])
    end
    if $cfg['simulator']['post_support'].nil?
      post_support = ''
    else
      post_support = squash('', $cfg['simulator']['post_support'])
    end
    return {:command => command, :pre_support => pre_support, :post_support => post_support}
  end
  
  def execute(command_string, verbose=true)
    report command_string
    output = `#{command_string}`.chomp
    report(output) if (verbose && !output.nil? && (output.length > 0))
    if $?.exitstatus != 0
      raise "Command failed. (Returned #{$?.exitstatus})"
    end
    return output
  end
  
  def report_summary
    summary = UnityTestSummary.new
    summary.set_root_path(HERE)
    results_glob = "#{$cfg['compiler']['build_path']}*.test*"
    results_glob.gsub!(/\\/, '/')
    results = Dir[results_glob]
    summary.set_targets(results)
    report summary.run
    raise "There were failures" if (summary.failures > 0)
  end
  
  def run_tests(test_files)
    
    report 'Running system tests...'
    
    # Tack on TEST define for compiling unit tests
    load_configuration($cfg_file)
    test_defines = ['TEST']
    $cfg['compiler']['defines']['items'] = [] if $cfg['compiler']['defines']['items'].nil?
    $cfg['compiler']['defines']['items'] << 'TEST'
    
    include_dirs = get_local_include_dirs
    
    # Build and execute each unit test
    test_files.each do |test|
      obj_list = []
      
      # Detect dependencies and build required required modules
      header_list = extract_headers(test) + ['cmock.h']
      header_list.each do |header|
      
        #create mocks if needed
        if (header =~ /Mock/) 
          require "../lib/cmock.rb" 
          @cmock ||= CMock.new($cfg_file) 
          @cmock.setup_mocks([$cfg['compiler']['source_path']+header.gsub('Mock','')])
        end
        
        # Compile corresponding source file if it exists
        src_file = find_source_file(header, include_dirs)
        if !src_file.nil?
          compile(src_file, test_defines)
          obj_list << header.ext($cfg['compiler']['object_files']['extension'])
        end
      end
      
      # Build the test runner (generate if configured to do so)
      test_base = File.basename(test, C_EXTENSION)
      runner_name = test_base + '_Runner.c'
      if $cfg['compiler']['runner_path'].nil?
        runner_path = $cfg['compiler']['build_path'] + runner_name
        test_gen = UnityTestRunnerGenerator.new($cfg_file)
        test_gen.run(test, runner_path)
      else
        runner_path = $cfg['compiler']['runner_path'] + runner_name
      end

      compile(runner_path, test_defines)
      obj_list << runner_name.ext($cfg['compiler']['object_files']['extension'])
      
      # Build the test module
      compile(test, test_defines)
      obj_list << test_base.ext($cfg['compiler']['object_files']['extension'])
      
      # Link the test executable
      link(test_base, obj_list)
      
      # Execute unit test and generate results file
      simulator = build_simulator_fields
      executable = $cfg['linker']['bin_files']['destination'] + test_base + $cfg['linker']['bin_files']['extension']
      if simulator.nil?
        cmd_str = executable
      else
        cmd_str = "#{simulator[:command]} #{simulator[:pre_support]} #{executable} #{simulator[:post_support]}"
      end
      output = execute(cmd_str)
      test_results = $cfg['compiler']['build_path'] + test_base
      if output.match(/OK$/m).nil?
        test_results += '.testfail'
      else
        test_results += '.testpass'
      end
      File.open(test_results, 'w') { |f| f.print output }
    end
  end
  
  def build_application(main)
  
    report "Building application..."
    
    obj_list = []
    load_configuration($cfg_file)
    main_path = $cfg['compiler']['source_path'] + main + C_EXTENSION

    # Detect dependencies and build required required modules
    include_dirs = get_local_include_dirs
    extract_headers(main_path).each do |header|
      src_file = find_source_file(header, include_dirs)
      if !src_file.nil?
        compile(src_file)
        obj_list << header.ext($cfg['compiler']['object_files']['extension'])
      end
    end
    
    # Build the main source file
    main_base = File.basename(main_path, C_EXTENSION)
    compile(main_path)
    obj_list << main_base.ext($cfg['compiler']['object_files']['extension'])
    
    # Create the executable
    link(main_base, obj_list)
  end
  
end
