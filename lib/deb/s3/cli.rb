require 'aws/s3'
require "thor"

require "deb/s3"
require "deb/s3/utils"
require "deb/s3/manifest"
require "deb/s3/package"
require "deb/s3/release"

class Deb::S3::CLI < Thor

  option :bucket,
    :required => true,
    :type     => :string,
    :desc     => "The name of the S3 bucket to upload to."

  option :codename,
    :default  => "stable",
    :type     => :string,
    :desc     => "The codename of the APT repository."

  option :section,
    :default  => "main",
    :type     => :string,
    :desc     => "The section of the APT repository."

  option :arch,
    :type     => :string,
    :desc     => "The architecture of the package in the APT repository."

  option :visibility,
    :default  => "public",
    :type     => :string,
    :desc     => "The access policy for the uploaded files. " +
                 "Can be public, private, or authenticated."

  option :access_key,
    :default  => "$AMAZON_ACCESS_KEY_ID",
    :type     => :string,
    :desc     => "The access key for connecting to S3."

  option :secret_key,
    :default  => "$AMAZON_SECRET_ACCESS_KEY",
    :type     => :string,
    :desc     => "The secret key for connecting to S3."

  desc "upload FILE",
    "Uploads the given FILE to a S3 bucket as an APT repository."
  def upload(file)
    # make sure the file exists
    error("File doesn't exist") unless File.exists?(file)

    # make sure we have a valid visibility setting
    visibility = case options[:visibility]
    when "public"
      :public_read
    when "private"
      :private
    when "authenticated"
      :authenticated_read
    else
      error("Invalid visibility setting given. Can be public, private, or authenticated.")
    end

    log("Examining package file #{File.basename(file)}")
    pkg = Deb::S3::Package.parse_file(file)

    # copy over some options if they weren't given
    arch = options[:arch] || pkg.architecture

    # validate we have them
    error("No architcture given and unable to determine one from the file. " +
      "Please specify one with --arch [i386,amd64].") unless arch

    # configure AWS::S3
    access_key = if options[:access_key] == "$AMAZON_ACCESS_KEY_ID"
      ENV["AMAZON_ACCESS_KEY_ID"]
    else
      options[:access_key]
    end
    secret_key = if options[:secret_key] == "$AMAZON_SECRET_ACCESS_KEY"
      ENV["AMAZON_SECRET_ACCESS_KEY"]
    else
      options[:secret_key]
    end
    error("No access key given for S3. Please specify one.") unless access_key
    error("No secret access key given for S3. Please specify one.") unless secret_key
    AWS::S3::Base.establish_connection!(
      :access_key_id     => access_key,
      :secret_access_key => secret_key
    )

    log("Retrieving existing package manifest")
    manifest = Deb::S3::Manifest.open(options[:bucket], options[:codename], options[:section], arch)

    # set the access policy
    manifest.policy = visibility

    # add in the package
    manifest.add(pkg)

    log("Uploading package and new manifests to S3")

    # create the i386 ones so apt-get doesn't cry
    # m = Deb::S3::Manifest.new
    # m.bucket = options[:bucket]
    # m.codename = options[:codename]
    # m.components << options[:section]
    # m.architecture = "i386"
    # m.policy = visibility
    # m.write_to_s3 do |f|
    #   sublog("Transferring #{f}")
    # end

    # do the main manifests
    manifest.write_to_s3 do |f|
      sublog("Transferring #{f}")
    end

    log("Update complete.")
  end

  private

  def log(message)
    puts ">> #{message}"
  end

  def sublog(message)
    puts "   -- #{message}"
  end

  def error(message)
    puts "!! #{message}"
    exit 1
  end

end