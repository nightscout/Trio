#!/usr/bin/env bash
# Rewrite Config.xcconfig identity keys for the current branch flavor.
# Fastlane parses Config.xcconfig line-by-line and skips #include, so the
# values must live in that file before any Fastlane lane runs.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

export FLAVORS_FILE="${REPO_ROOT}/.github/app-flavors.yml"
export CONFIG_FILE="${REPO_ROOT}/Config.xcconfig"
export BRANCH="${1:-${GITHUB_REF_NAME:-}}"

if [[ -z "${BRANCH}" ]]; then
  echo "usage: apply_app_flavor.sh <branch>" >&2
  exit 1
fi

if [[ ! -f "${FLAVORS_FILE}" ]]; then
  echo "error: missing flavor map ${FLAVORS_FILE}" >&2
  exit 1
fi

if [[ ! -f "${CONFIG_FILE}" ]]; then
  echo "error: missing ${CONFIG_FILE}" >&2
  exit 1
fi

ruby <<'RUBY'
require "yaml"

flavors_file = ENV.fetch("FLAVORS_FILE")
config_file = ENV.fetch("CONFIG_FILE")
branch = ENV.fetch("BRANCH")

data = YAML.load_file(flavors_file)
flavor_name = (data["branches"] || {}).fetch(branch, data.fetch("default_flavor"))
flavor = (data["flavors"] || {}).fetch(flavor_name) do
  raise "unknown flavor #{flavor_name.inspect} for branch #{branch.inspect}"
end

values = {
  "FLAVOR_NAME" => flavor_name,
  "APP_DISPLAY_NAME" => flavor.fetch("display_name"),
  "BUNDLE_IDENTIFIER" => flavor.fetch("bundle_identifier"),
  "APP_URL_SCHEME" => flavor.fetch("url_scheme"),
  "TRIO_APP_GROUP_ID" => flavor.fetch("app_group_id"),
  "UPSTREAM_BRANCH" => flavor["upstream_branch"].to_s,
  "FLAVOR_SCHEDULED_SYNC" => flavor["scheduled_sync"] ? "true" : "false",
  "FLAVOR_DISABLE_DEV_WARNING" => flavor["disable_dev_branch_warning"] ? "true" : "false"
}

replacements = {
  "APP_DISPLAY_NAME" => values["APP_DISPLAY_NAME"],
  "BUNDLE_IDENTIFIER" => values["BUNDLE_IDENTIFIER"],
  "APP_URL_SCHEME" => values["APP_URL_SCHEME"],
  "TRIO_APP_GROUP_ID" => values["TRIO_APP_GROUP_ID"]
}

updated = File.read(config_file)
replacements.each do |key, value|
  pattern = /^#{Regexp.escape(key)}\s*=\s*.*$/
  raise "missing #{key} assignment in #{config_file}" unless updated.match?(pattern)
  updated = updated.gsub(pattern, "#{key} = #{value}")
end
File.write(config_file, updated)

def write_github_file(path, values)
  return if path.to_s.empty?
  File.open(path, "a") do |io|
    values.each do |key, value|
      io.puts "#{key}<<EOF"
      io.puts value
      io.puts "EOF"
    end
  end
end

write_github_file(ENV["GITHUB_ENV"], values)
write_github_file(ENV["GITHUB_OUTPUT"], values)

puts "Applied flavor '#{values["FLAVOR_NAME"]}' for branch '#{branch}'"
values.each do |key, value|
  display = value.empty? ? "<none>" : value
  puts "  #{key}=#{display}"
end
RUBY
