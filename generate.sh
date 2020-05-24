# List of repositories to analyze
# Note: A dictionary instead of an array (possible future usage: an alias name for a repo having an internal name different from its external name)
declare -A repos
repos=([safe_browser]="" [safe-nodejs]="" [safe-api]="" [safe_client_libs]="" [quic-p2p]="" [safe_vault]="" [routing]=""
[safe-nd]="" [self_encryption]="" [parsec]="" [safe_app_csharp]="" [safe-authenticator-mobile]="" [safe-mobile-browser]="")

# Output file
dot=db.dot

# toml path
toml=toml-cli/target/debug/toml

# Dot file header
cat > $dot <<END_OF_HEADER
digraph g {
  stylesheet = "./db.css"
  graph[
    rankdir = "LR"
    splines = "spline"
  ];
  node[
    fontsize = "12"
    margin = "0.3,0.06"
    fontname = "verdana"
    shape = "record"
  ];
  edge[
    minlen=3
    color="DarkGreen"
    arrowhead="vee"
    arrowsize=0.5
  ];
END_OF_HEADER

# Download and build toml-cli if not already done
if [ ! -f "$toml" ]
then
    rm -rf toml-cli
    git clone https://github.com/gnprice/toml-cli
    cd toml-cli
    cargo build
    cd ..
fi

# - key is sub-repo name
# - value is repo name
declare -A repos_in_workspace

# - key is repo name or sub-repo name
# - value is a string containing dependencies separated with a white space
declare -A repos_dependencies

# Generate links
function analyze_dependencies () {
    dependencies=${repos_dependencies[$repo]}
    if [ "$dependencies" != "" ]
    then
        for dependency in $(echo $dependencies)
        do
            src_workspace=${repos_in_workspace[$repo]}
            dst_workspace=${repos_in_workspace[$dependency]}
            # Only links to listed repositories
            if [ $dst_workspace ] || [ -v repos[$dependency] ]
            then
                if [ $src_workspace ]
                then
                    printf "\"$src_workspace\":\"K_$repo\"" >> $dot
                else
                    printf "\"$repo\":\"K_$repo\"" >> $dot
                fi
                printf " -> " >> $dot
                if [ $dst_workspace ]
                then
                    printf "\"$dst_workspace\":\"K_$dependency\"" >> $dot
                else
                    printf "\"$dependency\":\"K_$dependency\"" >> $dot
                fi
                if [ $src_workspace ] && [ $dst_workspace ] && [ $src_workspace == $dst_workspace ]
                then
                    printf "\t[color=\"grey\"]" >> $dot
                fi
                printf "\n" >> $dot
            fi
        done
    fi
}

function set_repos_in_workspace () {
    for subdir in $*
    do
        repos_in_workspace[$subdir]=$repo
        printf "|<K_$subdir> $subdir" >> $dot
    done
}

for repo in "${!repos[@]}"
do
    # No root key for safe-api (because it is both a root crate and a sub-crate)
    if [ $repo == "safe-api" ]
    then
        root_key=""
    else
        root_key="<K_$repo> "
    fi
    printf "\n\"$repo\" [\n  label = \"$root_key\\N" >> $dot
    # Special cases for C# repos
    if [ $repo == "safe_app_csharp" ]
    then
        echo "Special case $repo"
        set_repos_in_workspace SafeApp SafeApp.AppBindings SafeApp.Core
        repos_dependencies["SafeApp.AppBindings"]="SafeApp.Core safe-ffi"
        repos_dependencies["SafeApp"]="SafeApp.AppBindings SafeApp.Core"
    elif [ $repo == "safe-authenticator-mobile" ]
    then
        echo "Special case $repo"
        repos_dependencies[$repo]="safe_authenticator_ffi"
    elif [ $repo == "safe-mobile-browser" ]
    then
        echo "Special case $repo"
        repos_dependencies[$repo]="safe_app_csharp"
    else
        echo "Analyzing $repo"
        # Test if it is a Rust repo by testing the most used language
        curl -s https://api.github.com/repos/maidsafe/$repo > repo.txt
        language=$(jq -r '.language' repo.txt)
        default_branch=$(jq -r '.default_branch' repo.txt)
        if [ $language == 'Rust' ]
        then
            # Test if root dir contains a Cargo.toml
            curl -s "https://raw.githubusercontent.com/maidsafe/$repo/$default_branch/Cargo.toml" > Cargo.toml
            if [ "$(<Cargo.toml)" == "404: Not Found" ]
            then
                # No Cargo.toml file at the root. This means it is a mixed repo like safe-nodejs (Rust + Javascript)
                dependencies=""
            else
                # This one could be null also (for a Rust repo with a workspace)
                dependencies=$($toml get Cargo.toml dependencies)
                if [ $(echo $dependencies | jq -r 'length') -ne 0 ]
                then
                    dependencies=$(echo $dependencies | jq -r 'keys[]')
                else
                    dependencies=""
                fi
            fi
            if [ "$dependencies" == "" ]
            then
                # Rust repo with a workspace or mixed repo
                if [ "$(<Cargo.toml)" == "404: Not Found" ]
                then
                    # Mixed repo => get root directories
                    curl -s https://api.github.com/repos/maidsafe/$repo/contents?ref=$default_branch > contents.txt
                    subdirs=$(jq -r '.[] | select(.type == "dir") .name' contents.txt)
                    rm contents.txt
                else
                    # Rust repo with a workspace => get [workspace] members
                    subdirs=$($toml get Cargo.toml workspace.members | jq -r '.[]')
                fi
                for subdir in $subdirs
                do
                    # Skip test subcrate
                    if [ $subdir != "tests" ] && [ $subdir != ".github" ]
                    then
                        # Include subcrates having a Cargo.tom file
                        curl -s "https://raw.githubusercontent.com/maidsafe/$repo/$default_branch/$subdir/Cargo.toml" > Cargo.toml
                        if [ "$(<Cargo.toml)" != "404: Not Found" ]
                        then
                            set_repos_in_workspace $subdir
                            repos_dependencies[$subdir]=$($toml get Cargo.toml dependencies | jq -r 'keys[]')
                        fi
                    fi
                done
            else
                # Regular Rust repo (with a Cargo.toml file at the root)
                repos_dependencies[$repo]=$dependencies
            fi
            rm Cargo.toml
        elif [ $language == 'JavaScript' ] || [ $language == 'TypeScript' ]
        then
            # Get dependencies from package.json file for JavaScript repo
            curl -s "https://raw.githubusercontent.com/maidsafe/$repo/$default_branch/package.json" > package.json
            dependencies=$(jq -r '.dependencies | keys[] | select(test("^[^@]"))' package.json)
            repos_dependencies[$repo]=$dependencies
            rm package.json
        fi
        rm repo.txt
    fi
    printf "\"\n]\n" >> $dot
done

printf "\n" >> $dot

for repo in "${!repos_dependencies[@]}"
do
    analyze_dependencies
done

# Dot file trailer
echo "}" >> $dot

# Generate svg file in build directory
rm -rf build
mkdir build
dot -T svg -o build/db.svg $dot

# Copy other files
cp db.css index.html build/
mv $dot build/
