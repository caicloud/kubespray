#!/usr/bin/env python
# -*- coding: utf-8 -*-
# @Note: This script is used for check tags and PR labels while release

import re
import os
import sys
import yaml
import time
import requests
import subprocess

informal_keys = "alpha|beta|rc"
fatal_color = "\033[41m"
success_color = "\033[42m"
info_color = "\033[43m"
default_color = "\033[0m"
ingore_label = ["platform-t2"]


def check_all(pull_url, chart_list_path, release_version, source_branch, github_token, jenkins_build_url):
    try:
        # checkout branch from commit_id
        branch_name = "update-tag"
        checkout_cmd = "git checkout -b {0} origin/{1}".format(branch_name, source_branch)
        exec_cmd(checkout_cmd)

        while True:
            exec_cmd("git pull origin {}".format(source_branch))
            # check PR merge status
            pull_info_data = get_pull_info(pull_url, github_token)
            merge_result = pull_info_data.get("merged")
            if merge_result:
                color_print("pull request merged", success_color)
                break

            # check informal tags
            # return true if no informal tags
            check_tags_result = check_tags(chart_list_path, release_version)
            # check labels and merge pr if check_tags_result is true
            check_labels(pull_url, github_token, jenkins_build_url, check_tags_result)

            time.sleep(10)

    except Exception as e:
        color_print("Check pr status failed due to: {}".format(e), fatal_color)
        sys.exit(1)
    finally:
        color_print("check pr status finished", success_color)


# function to check tags
def check_tags(chart_list_path, release_version):
    try:
        check_version_result = check_release_version(release_version)
        if check_version_result == "":
            color_print("{} is not rc version, do not check tags".format(release_version), fatal_color)
        else:
            color_print("{} is later than rc, start checking tags".format(release_version), success_color)
            all_chart_list_path = get_chart_liat_paths(chart_list_path)
            informal_tags = []
            for chart_list_path in all_chart_list_path:
                release_chart = yaml.safe_load(open(chart_list_path, 'r'))
                chart_spec = release_chart.get("spec")
                # get image name and version tag
                for chart in chart_spec:
                    repository_name = chart.get("repositoryFullName").split("/")[1]
                    repo_tag = chart.get("currentTag")
                    # get informal tags and add to list
                    if re.search(informal_keys, repo_tag):
                        informal_tags.append("{0}: {1}".format(repository_name, repo_tag))
            if informal_tags:
                # write informal tags list to text file
                alert_msg = "\n".join(informal_tags)
                with open("informal_tags.txt", "w") as file:
                    file.write(alert_msg)
                    color_print(alert_msg)

                # release version later than rc.3
                # will block release if informal tags exist
                if check_version_result == "fatal":
                    with open("check_tag", "w") as file:
                        file.write("true")
                return False
            else:
                color_print("no informal tags found", success_color)

        return True

    except Exception as e:
        print("Checking tags failed due to: {}".format(e))
        sys.exit(1)


def check_labels(pull_url, github_token, jenkins_build_url, enable_merge=True):
    try:
        header = {
            "Authorization": "token {}".format(github_token)
        }

        approved = False
        pull_info_data = get_pull_info(pull_url, github_token)

        needed_label_list = []
        pull_body = pull_info_data.get("body")
        pattern = re.compile(r'@caicloud/.*\s')

        # list all needed labels
        needed_labels = re.findall(pattern, pull_body)
        if needed_labels:
            needed_label_list = needed_labels[0].strip().replace("@caicloud/", "").split(" ")
            needed_label_list = [i for i in needed_label_list if i not in ingore_label]

        # list all added labels
        label_list = []
        labels = pull_info_data.get("labels")
        for label in labels:
            label_name = label.get("name")
            label_pattern = re.compile(r'confirm/.*')
            if re.match(label_pattern, label_name):
                label_list.append(label_name.replace("confirm/", ""))
            # get approved label, do not add label again if the PR is already approved
            approved_pattern = re.compile(r'approved')
            if re.match(approved_pattern, label_name):
                approved = True

        # compare added labels with needed labels
        missed_list = []
        added_list = []
        for label in needed_label_list:
            if label not in label_list:
                missed_list.append(label)
            else:
                added_list.append(label)
        if missed_list:
            color_print("{0} labels matched: {1}".format(len(added_list), added_list), success_color)
            color_print("{0} labels not matched: {1}".format(len(missed_list), missed_list), fatal_color)
        # no missed labels but tag checking failed, unable to merge
        elif not missed_list and not enable_merge:
            color_print("all labels matched, but informals tags found", fatal_color)
        # no missed labels and tag checking succeed, able to merge
        elif not missed_list and enable_merge:
            color_print("all labels matched and no informal tags, waiting for PR to be merged", success_color)
            # all labels matched, able to merge
            if not approved:
                # add lgtm and approve label and add comment
                add_label_comment(pull_info_data, jenkins_build_url, header)

    except Exception as e:
        color_print("Check labels failed due to: {}".format(e), fatal_color)
        sys.exit(1)


def merge_pull_request(pull_url, github_token, jenkins_build_url):
    try:
        header = {
            "Authorization": "token {}".format(github_token)
        }

        pull_info_data = get_pull_info(pull_url, github_token)

        # add lgtm and approve label and add comment
        add_label_comment(pull_info_data, jenkins_build_url, header)

    except Exception as e:
        color_print("merge pull request failed due to: {}".format(e), fatal_color)
        sys.exit(1)


def add_label_comment(pull_info_data, jenkins_build_url, header):
        color_print("add lgtm and approved label")
        label_url = pull_info_data.get("issue_url") + "/labels"
        data = {
            "labels": ["lgtm", "approved"]
        }
        # add lgtm and approved labels
        resp = requests.post(label_url, headers=header, json=data, timeout=60)
        if resp.status_code != 200:
            raise Exception(resp.text)
        # add comment
        color_print("add comment")
        merge_comment = "[Auto merged] This PR is **APPROVED by Jenkins.** \n\n Check Jenkins pipeline detail [here]({})".format(jenkins_build_url)
        comments_url = pull_info_data.get("comments_url")
        comment_data = {
            "body": merge_comment
        }
        resp = requests.post(comments_url, headers=header, json=comment_data, timeout=60)
        if resp.status_code != 201:
            raise Exception(resp.text)


def get_pull_info(pull_url, github_token):
    header = {
        "Authorization": "token {}".format(github_token)
    }
    resp = requests.get(pull_url, headers=header, timeout=60)
    if resp.status_code != 200:
        raise Exception(resp.text)
    pull_info_data = resp.json()

    return pull_info_data


# print log with color, print yellow of info level if color not set
def color_print(text, color=info_color, default_color=default_color):
    print("{0} {1} {2}".format(color, text, default_color))


# function to exec shell command and to deal with error
def exec_cmd(command):
    result = subprocess.getstatusoutput(command)
    return_code = result[0]
    return_text = result[1]
    if return_code != 0:
        raise Exception(return_text)
    else:
        print("Command run successfully: {}".format(command))


def check_release_version(release_version):
    # before rc release versions, return empty string, do not check tags
    # rc release version which earlier than rc.3, return "warning", check tags and only alert
    # release version which later than rc.3, return "fatal", check tags and block release
    check_result = ""
    formal_verison_pattern = "v?[\d]+\.[\d]+\.[\d]$"
    if re.match(formal_verison_pattern, release_version):
        check_result = "fatal"
    else:
        # rc version like v0.0.1-rc.3, return true if version later than rc.3
        rc_version_pattern = "v?[\d]+\.[\d]+\.[\d]+-rc.[\d]+"
        if re.match(rc_version_pattern, release_version):
            version_end = release_version.split(".")[-1]
            if int(version_end) >= 3:
                check_result = "fatal"
            elif 0 < int(version_end) < 3:
                check_result = "warning"
    return check_result


def get_chart_liat_paths(chart_list_path):
    all_chart_list_path = []
    if not os.path.exists(chart_list_path):
        print('{} can not be found'.format(chart_list_path))
        sys.exit(1)
    if os.path.isfile(chart_list_path):
        if chart_list_path.endswith('.yaml'):
            all_chart_list_path.append(chart_list_path)
    else:
        for dirpath, dirnames, filenames in os.walk(chart_list_path):
            for filename in filenames:
                if filename.endswith('.yaml'):
                    list_path = os.path.join(dirpath, filename)
                    all_chart_list_path.append(list_path)
    return all_chart_list_path


def main():
    check_type = sys.argv[1]

    if check_type == "tags":
        # only check tags
        color_print("start checking tags", success_color)
        chart_list_path = sys.argv[2]
        release_version = sys.argv[3]
        check_tags(chart_list_path, release_version)
    elif check_type == "labels":
        # only check labels
        color_print("start checking labels", success_color)
        github_token = sys.argv[2]
        jenkins_build_url = sys.argv[3]
        pull_url = sys.argv[4]
        while True:
            # check PR merge status
            pull_info_data = get_pull_info(pull_url, github_token)
            merge_result = pull_info_data.get("merged")
            if merge_result:
                color_print("pull request merged", success_color)
                break
            # check labels
            check_labels(pull_url, github_token, jenkins_build_url)
            time.sleep(10)
    elif check_type == "all":
        color_print("start checking tags and labels", success_color)
        # check tags and labels
        chart_list_path = sys.argv[2]
        release_version = sys.argv[3]
        source_branch = sys.argv[4]
        github_token = sys.argv[5]
        jenkins_build_url = sys.argv[6]
        pull_url = sys.argv[7]
        check_all(pull_url, chart_list_path, release_version, source_branch, github_token, jenkins_build_url)
    elif check_type == "merge":
        # directly merge, do not check tags and labels
        # merge pull request by add lgtm and approved labels
        color_print("directly merge the PR", success_color)
        github_token = sys.argv[2]
        jenkins_build_url = sys.argv[3]
        pull_url = sys.argv[4]
        # merge pull request
        merge_pull_request(pull_url, github_token, jenkins_build_url)
        while True:
            # check PR merge status
            pull_info_data = get_pull_info(pull_url, github_token)
            merge_result = pull_info_data.get("merged")
            if merge_result:
                color_print("pull request merged", success_color)
                break
            else:
                color_print("pull request not merged", fatal_color)
            time.sleep(10)
    else:
        color_print("do not check and quit")


if __name__ == '__main__':
    main()
