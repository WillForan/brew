# @private
module CompilerConstants
  GNU_GCC_VERSIONS = %w[4.4 4.5 4.6 4.7 4.8 4.9 5 6 7 8].freeze
  GNU_GCC_REGEXP = /^gcc-(4\.[4-9]|[5-8])$/.freeze
  COMPILER_SYMBOL_MAP = {
    "gcc"        => :gcc,
    "gcc-4.0"    => :gcc_4_0,
    "gcc-4.2"    => :gcc_4_2,
    "clang"      => :clang,
    "llvm_clang" => :llvm_clang,
  }.freeze

  COMPILERS = COMPILER_SYMBOL_MAP.values +
              GNU_GCC_VERSIONS.map { |n| "gcc-#{n}" }
end

class CompilerFailure
  attr_reader :name

  def version(val = nil)
    if val
      @version = Version.parse(val.to_s)
    else
      @version
    end
  end

  # Allows Apple compiler `fails_with` statements to keep using `build`
  # even though `build` and `version` are the same internally
  alias build version

  # The cause is no longer used so we need not hold a reference to the string
  def cause(_); end

  def self.for_standard(standard)
    COLLECTIONS.fetch(standard) do
      raise ArgumentError, "\"#{standard}\" is not a recognized standard"
    end
  end

  def self.create(spec, &block)
    # Non-Apple compilers are in the format fails_with compiler => version
    if spec.is_a?(Hash)
      _, major_version = spec.first
      name = "gcc-#{major_version}"
      # so fails_with :gcc => '4.8' simply marks all 4.8 releases incompatible
      version = "#{major_version}.999"
    else
      name = spec
      version = 9999
    end
    new(name, version, &block)
  end

  def initialize(name, version, &block)
    @name = name
    @version = Version.parse(version.to_s)
    instance_eval(&block) if block_given?
  end

  def fails_with?(compiler)
    name == compiler.name && version >= compiler.version
  end

  def inspect
    "#<#{self.class.name}: #{name} #{version}>"
  end

  COLLECTIONS = {
    cxx11:  [
      create(:gcc_4_0),
      create(:gcc_4_2),
      create(:clang) { build 425 },
      create(gcc: "4.4"),
      create(gcc: "4.5"),
      create(gcc: "4.6"),
    ],
    cxx14:  [
      create(:clang) { build 600 },
      create(:gcc_4_0),
      create(:gcc_4_2),
      create(gcc: "4.4"),
      create(gcc: "4.5"),
      create(gcc: "4.6"),
      create(gcc: "4.7"),
      create(gcc: "4.8"),
    ],
    openmp: [
      create(:clang),
    ],
  }.freeze
end

class CompilerSelector
  include CompilerConstants

  Compiler = Struct.new(:name, :version)

  COMPILER_PRIORITY = {
    clang:   [:clang, :gcc_4_2, :gnu, :gcc_4_0, :llvm_clang],
    gcc_4_2: [:gcc_4_2, :gnu, :clang, :gcc_4_0],
    gcc_4_0: [:gcc_4_0, :gcc_4_2, :gnu, :clang],
    gcc:     [:gnu, :gcc, :llvm_clang, :clang, :gcc_4_2, :gcc_4_0],
  }.freeze

  def self.select_for(formula, compilers = self.compilers)
    new(formula, DevelopmentTools, compilers).compiler
  end

  def self.compilers
    COMPILER_PRIORITY.fetch(DevelopmentTools.default_compiler)
  end

  attr_reader :formula, :failures, :versions, :compilers

  def initialize(formula, versions, compilers)
    @formula = formula
    @failures = formula.compiler_failures
    @versions = versions
    @compilers = compilers
  end

  def compiler
    find_compiler { |c| return c.name unless fails_with?(c) }
    raise CompilerSelectionError, formula
  end

  private

  def gnu_gcc_versions
    GNU_GCC_VERSIONS
  end

  def find_compiler
    compilers.each do |compiler|
      case compiler
      when :gnu
        gnu_gcc_versions.reverse_each do |v|
          name = "gcc-#{v}"
          version = compiler_version(name)
          yield Compiler.new(name, version) unless version.null?
        end
      when :llvm
        next # no-op. DSL supported, compiler is not.
      else
        version = compiler_version(compiler)
        yield Compiler.new(compiler, version) unless version.null?
      end
    end
  end

  def fails_with?(compiler)
    failures.any? { |failure| failure.fails_with?(compiler) }
  end

  def compiler_version(name)
    case name.to_s
    when "gcc", GNU_GCC_REGEXP
      versions.non_apple_gcc_version(name.to_s)
    else
      versions.send("#{name}_build_version")
    end
  end
end

require "extend/os/compilers"
