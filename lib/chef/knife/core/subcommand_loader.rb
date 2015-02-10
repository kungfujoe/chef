# Author:: Christopher Brown (<cb@opscode.com>)
# Author:: Daniel DeLeo (<dan@opscode.com>)
# Copyright:: Copyright (c) 2009, 2011 Opscode, Inc.
# License:: Apache License, Version 2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

require 'chef/version'
require 'chef/util/path_helper'
class Chef
  class Knife
    #
    # Public Methods of a Subcommand Loader
    #
    # load_commands            - loads all available subcommands
    # load_command(args)       - loads subcommands for the given args
    # list_commands(args)      - lists all available subcommands,
    #                            optionally filtering by category
    # subcommand_files         - returns an array of all subcommand files
    #                            that could be loaded
    # commnad_class_from(args) - returns the subcommand class for the
    #                            user-requested command
    #
    class SubcommandLoader
      attr_reader :chef_config_dir
      attr_reader :env

      # A small factory method.  Eventually, this is the only place
      # where SubcommandLoader should know about its subclasses, but
      # to maintain backwards compatibility many of the instance
      # methods in this base class contain default implementations
      # of the functions sub classes should otherwise provide
      # or directly instantiate the appropriate subclass
      def self.for_config
        if autogenerated_manifest?
          Knife::SubcommandLoader::HashedCommandLoader.new(chef_config_dir, plugin_manifest)
        elsif custom_manifest?
          Knife::SubcommandLoader::CustomManifestLoader.new(chef_config_dir, plugin_manifest)
        else
          Knife::SubcommandLoader::GemGlobLoader.new(chef_config_dir)
        end
      end

      def self.plugin_manifest?
        ENV["HOME"] && File.exist?(plugin_manifest_path)
      end

      def self.autogenerated_manifest?
        plugin_manifest? && plugin_manifest.key?('_autogenerated_command_paths')
      end

      def self.custom_manifest?
        plugin_manifest? && ! (plugin_manifest.keys - ['_autogenerated_command_paths']).empty?
      end

      def self.plugin_manifest
        @plugin_manifest ||= Chef::JSONCompat.from_json(File.read(plugin_manifest_path))
      end

      def self.plugin_manifest_path
        File.join(ENV['HOME'], '.chef', 'plugin_manifest.json')
      end

      def initialize(chef_config_dir, env = ENV)
        @chef_config_dir, @env = chef_config_dir, env
      end

      # Load all the sub-commands
      def load_commands
        subcommand_files.each { |subcommand| Kernel.load subcommand }
        true
      end

      def load_command(_command_args)
        load_commands
      end

      def list_commands(pref_cat = nil)
        load_commands
        if pref_cat && Chef::Knife.subcommands_by_category.key?(pref_cat)
          { pref_cat => Chef::Knife.subcommands_by_category[pref_cat] }
        else
          Chef::Knife.subcommands_by_category
        end
      end

      def command_class_from(args)
        cmd_words = positional_arguments(args)
        cmd_name = cmd_words.join('_')
        load_command(cmd_name)
        result = Chef::Knife.subcommands[find_longest_key(Chef::Knife.subcommands,
                                                          cmd_words, '_')]
        result || Chef::Knife.subcommands[args.first.gsub('-', '_')]
      end

      def guess_category(args)
        category_words = positional_arguments(args)
        category_words.map! { |w| w.split('-') }.flatten!
        find_longest_key(Chef::Knife.subcommands_by_category,
                         category_words, ' ')
      end

      #
      # Subclassses should define this themselves.  Eventually, this will raise a
      # NotImplemented error, but for now, we mimic the behavior the user was likely
      # to get in the past.
      def subcommand_files
        Chef::Log.warn "DEPRECATED: Using Chef::Knife::SubcommandLoader directly is deprecated.
Please use Chef::Knife::SubcommandLoader.for_config(chef_config_dir, env)"
        @subcommand_files ||= if Chef::Knife::SubcommandLoader.plugin_manifest?
                                Chef::Knife::SubcommandLoader::CustomManifestLoader.new(chef_config_dir, env).subcommand_files
                              else
                                Chef::Knife::SubcommandLoader::GemGlobLoader.new(chef_config_dir, env).subcommand_files
                              end
      end

      #
      # Utility function for finding an element in a hash given an array
      # of words and a separator.  We find the the longest key in the
      # hash composed of the given words joined by the separator.
      #
      def find_longest_key(hash, words, sep = '_')
        match = nil
        until match || words.empty?
          candidate = words.join(sep)
          if hash.key?(candidate)
            match = candidate
          else
            words.pop
          end
        end
        match
      end

      #
      # The positional arguments from the argument list provided by the
      # users. Used to search for subcommands and categories.
      #
      # @return [Array<String>]
      #
      def positional_arguments(args)
        args.select { |arg| arg =~ /^(([[:alnum:]])[[:alnum:]\_\-]+)$/ }
      end

      # Returns an Array of paths to knife commands located in
      # chef_config_dir/plugins/knife/ and ~/.chef/plugins/knife/
      def site_subcommands
        user_specific_files = []

        if chef_config_dir
          user_specific_files.concat Dir.glob(File.expand_path('plugins/knife/*.rb', Chef::Util::PathHelper.escape_glob(chef_config_dir)))
        end

        # finally search ~/.chef/plugins/knife/*.rb
        if env['HOME']
          user_specific_files.concat Dir.glob(File.join(Chef::Util::PathHelper.escape_glob(env['HOME'], '.chef', 'plugins', 'knife'), '*.rb'))
        end

        user_specific_files
      end
    end
  end
end
