#!/bin/bash

YML_LIST="cluster upgrade-cluster host-key scale remove-node reset extra_playbooks/upgrade-only-k8s"
INVENTORY="config/inventory"
LINT_PATH="."

rm -f linterr.txt stderr.txt

yaml_lint(){
    yamllint --no-warnings --strict ${LINT_PATH} > stderr.txt
    if [ $? -ne 0 ] || [ -s stderr.txt ]; then
        cat stderr.txt >> linterr.txt
        echo "-----------------------------------------" >> linterr.txt
    fi
}

ansible_check(){
    for file in ${YML_LIST}; do
        ansible-playbook -i ${INVENTORY} --syntax-check ${file}.yml 2> stderr.txt
        if [ $? -ne 0 ] || [ -s stderr.txt ]; then
            echo $file >> linterr.txt
            cat stderr.txt >> linterr.txt
            echo "-----------------------------------------" >> linterr.txt
        fi
    done
}

shell_check(){
    for file in $(find ${LINT_PATH} -name '*.sh' -not -path './contrib/*' -not -path './hack/*'); do
        shellcheck --severity error ${file} > stderr.txt
        if [ $? -ne 0 ] || [ -s stderr.txt ]; then
            echo $file >> linterr.txt
            cat stderr.txt >> linterr.txt
            echo "-----------------------------------------" >> linterr.txt
        fi
    done
}

check_output(){
    if [ -s linterr.txt ]; then
        echo "Error lint, please check following files:"
        echo "-----------------------------------------"
        cat linterr.txt
        echo "Repo lint failed."
        exit 1
    else
        echo "Successfully lint"
        rm -f linterr.txt stderr.txt
    fi
}

yaml_lint || true
shell_check || true
ansible_check || true
check_output
