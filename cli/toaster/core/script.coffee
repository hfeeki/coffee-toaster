ArrayUtil = require '../utils/array-util'

{log,debug,warn,error} = require '../utils/log-util'

module.exports = class Script

  # requires
  fs = require "fs"
  fsu = require 'fs-util'
  path = require 'path'
  cs = require "coffee-script"
  uglify = require("uglify-js").uglify
  uglify_parser = require("uglify-js").parser

  constructor: (@builder, @dirpath, @realpath) ->
    @getinfo()



  getinfo:( declare_ns = true )->
    # read file content and initialize dependencies and baseclasses array
    @raw = fs.readFileSync @realpath, "utf-8"
    @dependencies = []
    @baseclasses = []

    # assemble some information about the file
    @filepath = @realpath.replace "#{@dirpath}#{path.sep}", ''
    @filepath = (@filepath.substr 1) if (@filepath.substr 0, 1) is path.sep
    @filename = path.basename @filepath
    @filefolder = path.dirname @filepath

    # compute all necessary release paths
    release_file = path.join @builder.config.release_dir, @filepath
    release_file = release_file.replace '.coffee', '.js'
    release_dir = path.dirname release_file

    relative_path = release_file.replace @builder.toaster.basepath, ''
    relative_path = relative_path.substr 1 if relative_path[0] is path.sep

    # this info is used when compiling or deleting from disk, see methods
    # `delete_from_disk` and `compile_to_disk`
    @release = 
      folder: release_dir
      file: release_file
      relative: relative_path

    # TODO: REVIEW BLOCK BELLOW

    # cleaning filepath and 
    @namespace = ""

    # if the file is in the top level
    if @filepath.indexOf( path.sep ) is -1
      @filefolder = ""

    # assemble namespace info about the file by:
    # 1) replacing "/" or "\" by "."
    @namespace = @filefolder.replace (new RegExp "\\#{path.sep}", "g"), "."
    # 2) excluding first and last ".", if there's one
    @namespace = @namespace.replace /^\.?(.*)\.?$/g, "$1"

    # filter files that have class declarations inside of it
    rgx = /^(class)+\s+([^\s]+)+(\s(extends)\s+([\w.]+))?/mg

    # filter classes that extends another classes
    rgx_ext = /(^|=\s*)(class)\s(\w+)\s(extends)\s(\\w+)\s*$/gm


    # if there is a class inside the file
    if @raw.match( rgx )?

      # @classname = @raw.match( rgx )[3]
      @classname = (@raw.match /class\s([^\s]+)/)[1]
      @classpath = "#{@namespace}.#{@classname}"

      # colletcts the base classes, in case some class in the file
      # extends something
      for klass in @raw.match( rgx_ext ) ? []
        baseclass = klass.match( rgx_ext )[5]
        @baseclasses.push baseclass

    # TODO: REVIEW BLOCK ABOVE

    # dependencies regexp
    require_reg_all = /^([^\s]+)\s*=\s*require\s(?:'|")(.*)(?:'|")/mg
    require_reg_one = /^([^\s]+)\s*=\s*require\s(?:'|")(.*)(?:'|")/m

    # if file has one or more dependency
    if require_reg_all.test @raw

      # collect all and loop through them
      deps = @raw.match require_reg_all
      for dep in deps
        
        # comment line to strip it out from the compiled version
        @raw = @raw.replace dep, "# #{dep}"

        # computes dep name and path
        match = dep.match require_reg_one
        dep = 
          name: match[1]
          path: match[2] + '.coffee'
          vendor: false

        if dep.path[0] is ':'
          # dep.path = dep.path.substr 1
          dep.is_vendor = true

        # TODO: REVIEW BLOCK BELLOW
        # if user is under windows, checks and replace any "/" by "\" in
        # file dependencies: TODO: revise this
        # item.path = item.path.replace /(\/)/g, "\\" if path.sep == "\\"
        # TODO: REVIEW BLOCK ABOVE

        # and add it to the dependencies array
        @dependencies.push dep

    # saves the orignal raw file
    @backup = @raw

    # and inject AMD definitions
    @inject_definitions()

  # inject AMD definitions
  inject_definitions:->

    # computes all dependencies and format it as a stringfied array without []
    deps_path = ''
    deps_args = ''

    for dep in @dependencies
      deps_path += "'#{dep.path.replace '.coffee', ''}',\n" 
      deps_args += "#{dep.name}," unless dep.is_vendor

    deps_path = deps_path.slice 0, -1
    deps_args = deps_args.slice 0, -1

    # detect file identation style..
    match_identation = /^([\s]+).*$/mg
    identation = ''
    while not (identation.match /^[\s\t]{2,}/m)?
      identation = (match_identation.exec @raw)
      if identation?
        identation = identation[1]
      else
        identation = "  "

    # and reident content (will be wrapped by AMD closures)
    idented = @backup.replace /^/mg, "#{identation}"

    # re-process the raw file with AMD definitions (modules WITHOUT id)
    @raw = "define [#{deps_path}], ( #{deps_args} )-> \n#{idented}"

    # re-process the raw file with AMD definitions (modules WITH id)
    def = @filepath.replace '.coffee', ''
    @defined_raw = "define '#{def}', [#{deps_path}], ( #{deps_args} )-> \n#{idented}"

  # deletes release file from disk
  delete_from_disk:->
    fs.unlinkSync @release.file if (fs.existsSync @release.file)

  # compile release file to disk
  compile_to_disk:->
    # datetime for CLI notifications
    now = ("#{new Date}".match /[0-9]{2}\:[0-9]{2}\:[0-9]{2}/)[0]

    # get compiled javascript
    compiled = @compile_to_str()

    # create container folder if it doesnt exist yet
    fsu.mkdir_p @release.folder unless fs.existsSync @release.folder

    # write compile file inside of it
    fs.writeFileSync @release.file, compiled

    # notify user through cli
    msg = '✓ Compiled'.bold
    log "[#{now}] #{msg} #{@release.relative}".green

  # compile file and returns it as string
  compile_to_str:( add_definitions = false )->
    raw = if add_definitions then @defined_raw else @raw
    compiled = cs.compile raw, bare: @builder.config.bare

    # if toaster is runnig 
    if @builder.cli.argv.r and @builder.config.minify
      ast = uglify_parser.parse compiled
      ast = uglify.ast_mangle ast
      ast = uglify.ast_squeeze ast
      compiled = uglify.gen_code ast

    return compiled