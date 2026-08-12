#!/bin/bash
#
# redmine-plugin-work-report-exporter
# Copyright (C) 2022  Sutou Kouhei <kou@clear-code.com>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

set -exu

branch=${1:-5.1-stable}
rdbms=${2:-sqlite3}

tar \
  -cf plugin.tar \
  -v \
  --exclude-vcs \
  --exclude-vcs-ignores \
  .
git clone \
  --depth 1 \
  --branch ${branch} \
  https://github.com/redmine/redmine.git \
  redmine
mkdir -p redmine/plugins/testcase_management
tar \
  -xf plugin.tar \
  -C redmine/plugins/testcase_management

cd redmine
case ${rdbms} in
    postgresql)
	sed -e 's/localhost/postgres/' \
	    plugins/testcase_management/config/database.yml.example.postgresql | tee config/database.yml
	shift
	;;
    *)
	ln -s \
	   ../plugins/testcase_management/config/database.yml.example.sqlite3 \
	   config/database.yml
	shift
	;;
esac
bundle install
cp plugins/testcase_management/test/fixtures/*.yml test/fixtures/
cp plugins/testcase_management/test/fixtures/files/*.csv test/fixtures/files/
bin/rails db:create
bin/rails generate_secret_token
bin/rails db:migrate
bin/rails redmine:plugins:migrate
bin/rails redmine:load_default_data REDMINE_LANG=en
cd -
