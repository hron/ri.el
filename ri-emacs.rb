## ri-emacs.rb helper script for use with ri-ruby.el
#
# Author: Kristof Bastiaensen <kristof@vleeuwen.org>
#
#
#    Copyright (C) 2004,2006 Kristof Bastiaensen
#
#    This program is free software; you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation; either version 2 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program; if not, write to the Free Software
#    Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
#----------------------------------------------------------------------
#
#  For information on how to use and install see ri-ruby.el
#

# This script has been updated to work with RDoc 2, which comes with
# Ruby 1.9 and is also available in gem form. If you are having
# trouble with it in Ruby 1.8, try installing the "rdoc" gem.

# As of the 10th of September, RDoc 2.1.0 is the latest released
# version, and there have been some required fixes since that
# release. So if you're having trouble, try installing RDoc from
# trunk:

# $ svn co svn://rubyforge.org/var/svn/rdoc/trunk rdoc
# $ cd rdoc && rake install_gem

require 'rubygems'
require 'rdoc/ri'
require 'rdoc/ri/paths'
require 'rdoc/ri/writer'
require 'rdoc/ri/cache'
require 'rdoc/ri/util'
require 'rdoc/ri/reader'
require 'rdoc/ri/formatter'
require 'rdoc/ri/display'

module RDoc::RI
  class Emacs
    def initialize
      @ri_reader = Reader.new(Cache.new(Paths.path(true, true, true, true)))
      @display = Display.new(Formatter.for("ansi"), 72, true)
    end

    def lookup_keyw(keyw)
      desc = NameDescriptor.new(keyw)

      namespace = @ri_reader.top_level_namespace
      class_name = nil
      container = desc.class_names.inject(namespace) do |container, class_name|
        namespace = @ri_reader.lookup_namespace_in(class_name, container)
        namespace.find_all {|m| m.name == class_name}
      end

      if desc.method_name.nil?
        if [?., ?:, ?#].include? keyw[-1]
          namespaces = @ri_reader.lookup_namespace_in("", container)
          is_class_method = case keyw[-1]
                            when ?.: nil
                            when ?:: true
                            when ?#: false
                            end
          methods = @ri_reader.find_methods("", is_class_method,
                                            container)
          return nil if methods.empty? && namespaces.empty?
        else
          #class_name = desc.class_names.last
          namespaces = namespace.find_all{ |n| n.name.index(class_name).zero? }
          return nil if namespaces.empty?
          methods = []
        end
      else
        return nil if container.empty?
        namespaces = []
        methods = @ri_reader.
          find_methods(desc.method_name,
                       desc.is_class_method,
                       container).
          find_all { |m| m.name.index(desc.method_name).zero? }
        return nil if methods.empty?
      end

      return desc, methods, namespaces
    end

    def completion_list(keyw)
      return @ri_reader.full_class_names if keyw == ""

      desc, methods, namespaces = lookup_keyw(keyw)
      return nil unless desc

      if desc.class_names.empty?
        return methods.map { |m| m.name }.uniq
      else
        return methods.map { |m| m.full_name } +
          namespaces.map { |n| n.full_name }
      end
    end

    def complete(keyw, type = :all)
      list = completion_list(keyw)

      if list.nil?
        return "nil"
      elsif type == :all
        return "(" + list.map { |w| w.inspect }.join(" ") + ")"
      elsif type == :lambda
        if list.find { |n|
            n.split(/(::)|#|\./) == keyw.split(/(::)|#|\./) }
          return "t"
        else
          return "nil"
        end
        # type == try
      elsif list.size == 1 and
          list[0].split(/(::)|#|\./) == keyw.split(/(::)|#|\./)
        return "t"
      end

      first = list.shift;
      if first =~ /(.*)((?:::)|(?:#))(.*)/
        other = $1 + ($2 == "::" ? "#" : "::") + $3
      end

      len = first.size
      match_both = false
      list.each do |w|
        while w[0, len] != first[0, len]
          if other and w[0, len] == other[0, len]
            match_both = true
            break
          end
          len -= 1
        end
      end

      if match_both
        return other.sub(/(.*)((?:::)|(?:#))/) {
          $1 + "." }[0, len].inspect
      else
        return first[0, len].inspect
      end
    end

    def display_info(keyw)
      desc, methods, namespaces = lookup_keyw(keyw)
      return false if desc.nil?

      if desc.method_name
        methods = methods.find_all { |m| m.name == desc.method_name }
        return false if methods.empty?
        meth = @ri_reader.get_method(methods[0])
        @display.display_method_info(meth)
      else
        namespaces = namespaces.find_all { |n| n.full_name == desc.full_class_name }
        return false if namespaces.empty?
        klass = @ri_reader.get_class(namespaces[0])
        @display.display_class_info(klass)
      end

      return true
    end

    def display_args(keyw)
      desc, methods, namespaces = lookup_keyw(keyw)
      return nil unless desc && desc.class_names.empty?

      methods = methods.find_all { |m| m.name == desc.method_name }
      return false if methods.empty?
      methods.each do |m|
        meth = @ri_reader.get_method(m)
        @display.full_params(meth)
      end

      return true
    end

    # return a list of classes for the method keyw
    # return nil if keyw has already a class
    def class_list(keyw, rep='\1')
      desc, methods, namespaces = lookup_keyw(keyw)
      return nil unless desc && desc.class_names.empty?

      methods = methods.find_all { |m| m.name == desc.method_name }

      return "(" + methods.map do |m|
        "(" + m.full_name.sub(/(.*)(#|(::)).*/,
                              rep).inspect + ")"
      end.uniq.join(" ") + ")"
    end

    # flag means (#|::)
    # return a list of classes and flag for the method keyw
    # return nil if keyw has already a class
    def class_list_with_flag(keyw)
      class_list(keyw, '\1\2')
    end

    class Command
      def initialize(ri, input = STDIN, out = STDOUT)
        @out, @in = [out, input]
        @out.sync = true
        @ri = ri
      end

      def read_next
        line = @in.gets
        cmd, param = /(\w+)(.*)$/.match(line)[1..2]
        send(cmd.downcase.intern, param.strip)
      end

      def try_completion(keyw)
        @out.puts @ri.complete(keyw, :try)
      end

      def complete_all(keyw)
        @out.puts @ri.complete(keyw, :all)
      end

      def lambda(keyw)
        @out.puts @ri.complete(keyw, :lambda)
      end

      def class_list(keyw)
        @out.puts @ri.class_list(keyw)
      end

      def class_list_with_flag(keyw)
        @out.puts @ri.class_list_with_flag(keyw)
      end

      def display_args(keyw)
        @ri.display_args(keyw)
        @out.puts "RI_EMACS_END_OF_INFO"
      end

      def display_info(keyw)
        @ri.display_info(keyw)
        @out.puts "RI_EMACS_END_OF_INFO"
      end
    end
  end
end

if __FILE__ == $0
  cmd = RDoc::RI::Emacs::Command.new(RDoc::RI::Emacs.new)
  STDOUT.puts 'READY'
  loop { cmd.read_next }
end
