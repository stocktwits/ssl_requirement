require "#{File.dirname(__FILE__)}/url_for"
require "active_support/core_ext/class"

# Copyright (c) 2005 David Heinemeier Hansson
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
module SslRequirement
  extend ActiveSupport::Concern

  mattr_writer :ssl_host, :ssl_port, :non_ssl_host, :non_ssl_port,
    :disable_ssl_check, :ssl_header
  mattr_accessor :redirect_status

  def self.ssl_host
    determine_host(@@ssl_host) rescue nil
  end

  def self.ssl_port
    @@ssl_port ||= 443
  end

  def self.non_ssl_host
    determine_host(@@non_ssl_host) rescue nil
  end

  def self.non_ssl_port
    @@non_ssl_port ||= 80
  end

  # mattr_reader would generate both ssl_host and self.ssl_host
  def ssl_host
    SslRequirement.ssl_host
  end

  def ssl_port
    SslRequirement.ssl_port
  end

  def non_ssl_host
    SslRequirement.non_ssl_host
  end

  def non_ssl_port
    SslRequirement.non_ssl_port
  end

  def self.disable_ssl_check?
    @@disable_ssl_check ||= false
  end
  
  def self.ssl_header
    @@ssl_header ||= false
  end

  included do
    class_attribute :ssl_required_actions
    class_attribute :ssl_required_except_actions
    class_attribute :ssl_allowed_actions

    before_filter :ensure_proper_protocol
  end

  module ClassMethods
    # Specifies that the named actions requires an SSL connection to be performed (which is enforced by ensure_proper_protocol).
    def ssl_required(*actions)
      self.ssl_required_actions ||= []
      self.ssl_required_actions += actions
    end

    def ssl_exceptions(*actions)
      self.ssl_required_except_actions ||= []
      self.ssl_required_except_actions += actions
    end

    # To allow SSL for any action pass :all as action like this:
    # ssl_allowed :all
    def ssl_allowed(*actions)
      self.ssl_allowed_actions ||= []
      self.ssl_allowed_actions += actions
    end
  end

  protected
  # Returns true if the current action is supposed to run as SSL
  def ssl_required?
    required = self.class.ssl_required_actions || []
    except  = self.class.ssl_required_except_actions

    unless except
      required.include?(action_name.to_sym)
    else
      !except.include?(action_name.to_sym)
    end
  end

  def ssl_allowed?
    allowed_actions = self.class.ssl_allowed_actions || []

    allowed_actions == [:all] || allowed_actions.include?(action_name.to_sym)
  end

  # normal ports are the ports used when no port is specified by the user to the browser
  # i.e. 80 if the protocol is http, 443 is the protocol is https
  NORMAL_PORTS = [80, 443]

  private
  def is_header_ssl(request)
    ssl_header && request.headers[ ssl_header ].present?
  end

  def is_ssl(request)
    request.ssl? || is_header_ssl(request)
  end

  def ensure_proper_protocol
    return true if SslRequirement.disable_ssl_check?

    if ssl_required? && !is_ssl(request)
      redirect_to determine_redirect_url(request, true), :status => (redirect_status || :found)
      flash.keep
      return false
    elsif is_ssl(request) && ssl_allowed?
      return true
    elsif is_ssl(request) && !ssl_required?
      redirect_to determine_redirect_url(request, false), :status => (redirect_status || :found)
      flash.keep
      return false
    end
  end

  def determine_redirect_url(request, ssl)
    protocol = ssl ? "https" : "http"
    "#{protocol}://#{determine_host_and_port(request, ssl)}#{request.fullpath}"
  end

  def determine_host_and_port(request, ssl)
    request_host = request.host
    request_port = request.port

    if ssl
      "#{ssl_host || request_host}#{determine_ssl_port_string request.port}"
    else
      "#{non_ssl_host || request_host}#{determine_non_ssl_port_string request.port}"
    end
  end

  def determine_ssl_port_string(request_port)
    if request_port == non_ssl_port
      port = ssl_port
    else
      port = request_port || ssl_port
    end
    determine_port_string port
  end

  def determine_non_ssl_port_string(request_port)
    if request_port == ssl_port
      port = non_ssl_port
    else
      port = request_port || non_ssl_port
    end
    determine_port_string port
  end

  def self.determine_host(host)
    if host.is_a?(Proc) || host.respond_to?(:call)
      host.call
    else
      host
    end
  end

  def determine_port_string(port)
    unless port_normal?(port)
      ":#{port}"
    else
      ""
    end
  end

  def port_normal?(port)
    NORMAL_PORTS.include?(port)
  end
end
