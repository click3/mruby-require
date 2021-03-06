MRuby::Gem::Specification.new('mruby-require') do |spec|
  spec.license = 'MIT'
  spec.authors = 'mattn'
  ENV["MRUBY_REQUIRE"] = ""
  @bundled = []

  is_vc = ENV['OS'] == 'Windows_NT' && cc.command =~ /^cl(\.exe)?$/
  #cc.defines << "/LD" if is_vc
  top_build_dir = build_dir
  MRuby.each_target do
    if enable_gems?
      top_build_dir = build_dir
      gemlist = []
      gems.each do |x|
        gemlist << x
      end
      @bundled = gemlist.uniq {|x| x.name}.clone.reject {|g| g.authors == 'mruby developers' || g.name == 'mruby-require'}
      sharedlibs = {}
      gemlist.reject! {|g| g.authors == 'mruby developers' }
      @bundled.each do |g|
        sharedlib = "#{top_build_dir}/lib/#{g.name}.so"
        ENV["MRUBY_REQUIRE"] += "#{g.name},"
        objs = g.objs ? g.objs : []
        if File.exist?("#{build_dir}/mrbgem/#{g.name}/gem_init.c")
          objs << "#{build_dir}/mrbgem/#{g.name}/gem_init.c"
        end
        sharedlibs[sharedlib] = objs
        file sharedlib => objs do |t|
          has_rb = !Dir.glob("#{g.dir}/mrblib/*.rb").empty?
          has_c = !Dir.glob(["#{g.dir}/src/*"]).empty?
          if RUBY_PLATFORM.downcase == /mswin(?!ce)|mingw|bccwin/
            name = g.name.gsub(/-/, '_')
            deffile = "#{build_dir}/lib/#{g.name}.def"
            open(deffile, 'w') do |f|
              f.puts %Q[EXPORTS]
              f.puts %Q[	gem_mrblib_irep_#{name}] if has_rb
              f.puts %Q[	mrb_#{name}_gem_init] if has_c
              f.puts %Q[	mrb_#{name}_gem_final] if has_c
            end
          else
            deffile = ''
          end
          options = {
              :flags => [
                  is_vc ? '/DLL' : '-shared -fPIC',
                  (g.linker ? g.linker.library_paths : []).flatten.map {|l| is_vc ? "/LIBPATH:#{l}" : "-L#{l}"}].flatten.join(" "),
              :outfile => sharedlib,
              :objs => [sharedlibs[t.name]].flatten.join(" "),
              :libs => [
                  (is_vc ? '/DEF:' : '') + deffile,
                  libfile("#{build_dir}/lib/libmruby"),
                  libfile("#{build_dir}/lib/libmruby_core"),
                  (g.linker ? g.linker.libraries : []).flatten.uniq.map {|l| is_vc ? "#{l}.lib" : "-l#{l}"}].flatten.join(" "),
              :flags_before_libraries => '',
              :flags_after_libraries => '',
          }

          _pp "LD", sharedlib
          sh linker.command + ' ' + (linker.link_options % options)
        end

        file sharedlib => libfile("#{top_build_dir}/lib/libmruby")

        Rake::Task.tasks << sharedlib
      end
      libmruby.flatten!.reject! {|l|
        @bundled.reject {|g| l.index(g.name) == nil}.size > 0
      }
      cc.include_paths.reject! {|l|
        @bundled.reject {|g| l.index(g.name) == nil}.size > 0
      }
    end
  end
  module MRuby
    class Build
      alias_method :old_print_build_summary_for_require, :print_build_summary
      def print_build_summary 
        old_print_build_summary_for_require

        Rake::Task.tasks.each do |t|
          if t.name =~ /\.so$/
            t.invoke
          end
        end

        unless @bundled.empty?
          puts "================================================"
            puts "     Bundled Gems:"
            @bundled.map(&:name).each do |name|
            puts "             #{name}"
          end
          puts "================================================"
        end
      end
    end
  end

  spec.cc.include_paths << ["#{build.root}/src"]
  if RUBY_PLATFORM.downcase !~ /mswin(?!ce)|mingw|bccwin/
    spec.linker.libraries << ['dl']
    spec.cc.flags << "-DMRBGEMS_ROOT=\\\"#{File.expand_path top_build_dir}/lib\\\""
  else
    spec.cc.flags << "-DMRBGEMS_ROOT=\"\"\"#{File.expand_path top_build_dir}/lib\"\"\""
  end
end
