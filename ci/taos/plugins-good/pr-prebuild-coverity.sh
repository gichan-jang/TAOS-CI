#!/usr/bin/env bash

##
# Copyright (c) 2019 Samsung Electronics Co., Ltd. All Rights Reserved.
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#     http://www.apache.org/licenses/LICENSE-2.0
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

##
# @file     pr-prebuild-coverity.sh
# @brief    This module examines C/C++ source code to find defects and security vulnerabilities
#
#  Coverity is a static code analysis tool from Synopsys. This product enables engineers and security teams
#  to quickly find and fix defects and security vulnerabilities in custom source code written in C, C++, 
#  Java, C#, JavaScript and more.
#	
#  Coverity Scan is a free static-analysis cloud-based service for the open source community. 
#  The tool analyzes over 3900 open-source projects and is integrated with GitHub and Travis CI.
#
# @see      https://scan.coverity.com/github
# @see      https://scan.coverity.com/download?tab=cxx
# @see      https://github.com/nnsuite/TAOS-CI
# @author   Geunsik Lim <geunsik.lim@samsung.com>
# @note Supported build type: meson
# @note How to install the Coverity package
#  $ firefox https://scan.coverity.com/download 
#  $ cd /opt
#  $ tar xvzf cov-analysis-linux64-2019.03.tar.gz
#  $ vi ~/.bashrc
#    # coverity path
#    export PATH=/opt/cov-analysis-linux64-2019.03/bin:$PATH
#  $ cov-build --dir cov-int <build_command>
#


## @brief A coverity web-crawler to fetch defects from scan.coverity.com
function coverity-crawl-defect {
    wget -a cov-report-defect-debug.txt -O cov-report-defect.html  https://scan.coverity.com/projects/nnsuite-nnstreamer

    # Check the frequency for build submissions to coverity scan
    # https://scan.coverity.com/faq#frequency
    # Up to 28 builds per week, with a maximum of 4 builds per day, for projects with fewer than 100K lines of code
    # Up to 21 builds per week, with a maximum of 3 builds per day, for projects with 100K to 500K lines of code
    # Up to 14 builds per week, with a maximum of 2 build per day, for projects with 500K to 1 million lines of code
    # Up to 7 builds per week, with a maximum of 1 build per day, for projects with more than 1 million lines of code
    time_limit=23  # unit is hour
    stat_last_build=$(cat ./cov-report-defect.html    | grep "Last build analyzed" -A 1 | tail -n 1 | cut -d'>' -f 2 | cut -d'<' -f 1)
    echo -e "Last build analyzed: $stat_last_build"

    stat_last_build_freq=$(echo $stat_last_build | grep "hour" | cut -d' ' -f 2)
    stat_last_build_quota_full=0
    echo -e "[DEBUG] ($stat_last_build_freq) hour"
    if [[ $stat_last_build_freq -gt 0 && $stat_last_build_freq -gt $time_limit ]]; then
        echo -e "Okay. Continuing the task because the last build passed $time_limit hours."
        stat_last_build_quota_full=0
    else
        echo -e "Ooops. Stopping the task because the last build is less than $time_limit hours."
        stat_last_build_quota_full=1
    fi

    # Fetch the defect, outstadning, dismissed, fixed from scan.coverity.com
    stat_total_defects=$(cat ./cov-report-defect.html | grep "Total defects" -B 1 | head -n 1 | cut -d'<' -f3 | cut -d'>' -f2 | tr -d '\n')
    echo -e "Total defects: $stat_total_defects"

    stat_outstanding=$(cat ./cov-report-defect.html   | grep "Outstanding"   -B 1 | head -n 1 | cut -d'<' -f3 | cut -d'>' -f2 | tr -d '\n')
    echo -e "-Outstanding: $stat_outstanding"

    stat_dismissed=$(cat ./cov-report-defect.html     | grep "Dismissed"     -B 1 | head -n 1 | cut -d'<' -f3 | cut -d'>' -f2 | tr -d '\n')
    echo -e "-Dismissed: $stat_dismissed"

    stat_fixed=$(cat ./cov-report-defect.html         | grep "Fixed"         -B 1 | head -n 1 | cut -d'<' -f3 | cut -d'>' -f2 | tr -d '\n')
    echo -e "-Fixed: $stat_fixed"

    # TODO: we can get more additional information if we login at the 'build' webpage of scan.coverity.com.
    # https://scan.coverity.com/users/sign_in 
    if [[ $_login -eq 1 ]]; then
        wget -a cov-report-defect-build.txt -O cov-report-build.html  https://scan.coverity.com/projects/nnsuite-nnstreamer/builds/new?tab=upload
        stat_build_status=$(cat ./cov-report-build.html  | grep "Last Build Status:" )
        echo -e "Build Status: $stat_build_status"
    fi
}

# @brief [MODULE] TAOS/pr-prebuild-coverity
function pr-prebuild-coverity(){
    echo "########################################################################################"
    echo "[MODULE] TAOS/pr-prebuild-coverity: Check defects and security issues in C/C++ source codes with coverity"
    pwd

    # Check if server administrator install required commands
    check_cmd_dep file
    check_cmd_dep grep
    check_cmd_dep cat
    check_cmd_dep wc
    check_cmd_dep git
    check_cmd_dep tar
    check_cmd_dep cov-build
    check_cmd_dep curl
    check_cmd_dep meson
    check_cmd_dep ninja
    check_cmd_dep ccache

    check_result="skip"

    # Display the coverity version that is installed in the CI server.
    # Note that the out-of-date version can generate an incorrect result.
    coverity --version

    # Read file names that a contributor modified (e.g., added, moved, deleted, and updated) from a last commit.
    # Then, inspect C/C++ source code files from *.patch files of the last commit.
    FILELIST=`git show --pretty="format:" --name-only --diff-filter=AMRC`
    for i in ${FILELIST}; do
        # Skip the obsolete folder
        if [[ ${i} =~ ^obsolete/.* ]]; then
            continue
        fi
        # Skip the external folder
        if [[ ${i} =~ ^external/.* ]]; then
            continue
        fi
        # Handle only text files in case that there are lots of files in one commit.
        echo "[DEBUG] file name is (${i})."
        if [[ `file ${i} | grep "ASCII text" | wc -l` -gt 0 ]]; then
            # in case of C/C++ source code
            case ${i} in
                # in case of C/C++ code
                *.c|*.cc|*.cpp|*.c++)
                    # Check the defects of C/C++ file with coverity. The entire procedure is as following:

                    echo "[DEBUG] (${i}) file is source code with the text format."

                    # Step 1/4: run coverity (cov-build) to execute a static analysis
                    # configure the compiler type and compiler command.
                    # https://community.synopsys.com/s/article/While-using-ccache-prefix-to-build-project-c-primary-source-files-are-not-captured
                    # [NOTE] You need to change the variables appropriately if your project does not use ccache, gcc, and g++.
                    # The execution result of the coverity-build command is dependend on the build style of the source code.
                    cov-configure --comptype prefix --compiler ccache
                    cov-configure --comptype gcc --compiler cc
                    cov-configure --comptype g++ --compiler c++

                    analysis_sw="cov-build"
                    analysis_rules="--dir cov-int"
                    coverity_result="coverity_defects_result"

                    # Check the build submission qutoa for this project
                    # https://scan/coverity.com/faq#frequency
                    # Activity1: get build status from https://scan.coverity.com/projects/<your-github-project-name>/builds/new.
                    # Activity2: Check the current build submission quota
                    # Activity3: Stop or run the coverity scan service with the build quota
                    coverity-crawl-defect
        
                    if [[ $stat_last_build_quota_full -eq 1 ]]; then
                        echo -e "[DEBUG] Sorry. The build quota of the coverity scan is exceeded."
                        echo -e "[DEBUG] Stopping the coverity module."
                        break;
                    fi

                    # run the static analysis with coverity
                    if  [[ $_cov_build_type -eq "meson" ]]; then
                        build_cmd="ninja -C build-coverity"
                        rm -rf ./build-coverity/
                        meson build -C build-coverity
                        $analysis_sw $analysis_rules $build_cmd > ../report/${coverity_result}_${i}.txt
                        exec_result=`cat ../report/${coverity_result}_${i}.txt | grep "The cov-build utility completed successfully" | wc -l`
                    else
                        echo -e "[DEBUG] Sorry. We currently provide the meson build type."
                        echo -e "[DEBUG] If you want to add new build type, Please contribute the build type."
                        echo -e "[DEBUG] Stopping the coverity module."
                        check_result="skip"
                        break;
                    fi
                  
                    # Report the execution result.
                    if  [[ $exec_result -eq 0 ]]; then
                        echo "[DEBUG] $analysis_sw: failed. file name: ${i}, There execution result is $exec_result ."
                        check_result="failure"
                        global_check_result="failure"
                    else
                        echo "[DEBUG] $analysis_sw: passed. file name: ${i}, The execution result is $exec_result ."
                        check_result="success"

                    # Step 2/4: commit the otuput to scan.coverity.com
                        # commit the execution result of the coverity
                        _cov_version=$(date '+%Y%m%d-%H%M')
                        _cov_description="${date}-coverity"
                        _cov_file="cov_project.tgz"


                        # create a tar archive from  the results (the 'cov-int' folder).
                        tar cvzf $_cov_file cov-int

                        # Please make sure to include the '@' sign before the tarball file name.
                        curl --form token=$_cov_token \
                          --form email=$_cov_email \
                          --form file=@$_file \
                          --form version="$_cov_version" \
                          --form description="$_cov_description" \
                          $_cov_site \
                          -o curl_output.txt
                        result=$?
                       
                        # Note that curl gets value (0) even though you use a incorrect file name.
                        if [[ $result -eq 0 ]]; then
                            echo -e "Please visit https://scan.coverity.com/projects/<your-github-repository>"
                        else
                            echo -e "Ooops... The return value is $result. The coverity task is failed."
                        fi

                    fi
                    # Although source files are 1+, we just run once because coverity inspects all source files.
                    break
                    ;;
                * )
                    echo "[DEBUG] The coverity (a static analysis tool to find defects) module does not scan (${i}) file."
                    ;;
            esac
        fi
    done
   
    # Step 3/4: change the execution result of the coverity module according to the execution result 
    # TODO: Get additional information from https://scan.coverity.com with a webcrawler
    # 1. How can we know if coverity can be normally executed or not? with the curl_output.txt file
    # 2. How do we know the time that the coverity scan completes? with a webcrawler
    # 3. How do we check changes of defects between pre-PR and post-PR? with a webcrawler

    # Step 4/4: comment the summarized report on a PR if defects exist.
    if [[ $check_result == "success" ]]; then
        echo "[DEBUG] Passed. Static code analysis tool for security - coverity."
        message="Successfully coverity has done the static analysis."
        cibot_report $TOKEN "success" "TAOS/pr-prebuild-coverity" "$message" "$_cov_prj_website" "${GITHUB_WEBHOOK_API}/statuses/$input_commit"
    elif [[ $check_result == "skip" ]]; then
        echo "[DEBUG] Skipped. Static code analysis tool for security - coverity."
        message="Skipped. This module did not investigate your PR."
        cibot_report $TOKEN "success" "TAOS/pr-prebuild-coverity" "$message" "${CISERVER}${PRJ_REPO_UPSTREAM}/ci/${dir_commit}/" "${GITHUB_WEBHOOK_API}/statuses/$input_commit"
    else
        echo "[DEBUG] Failed. Static code analysis tool for security - coverity."
        message="Oooops. coverity is not completed. Please ask the CI administrator on this issue."
        cibot_report $TOKEN "failure" "TAOS/pr-prebuild-coverity" "$message" "${CISERVER}${PRJ_REPO_UPSTREAM}/ci/${dir_commit}/" "${GITHUB_WEBHOOK_API}/statuses/$input_commit"
    
        # Inform PR submitter of a hint in more detail
        message=":octocat: **cibot**: $user_id, **${i}** includes bug(s). Please fix security flaws in your commit before entering a review process."
        cibot_comment $TOKEN "$message" "$GITHUB_WEBHOOK_API/issues/$input_pr/comments"
    fi
    

}
