class Project
  include ActiveModel::Model
  attr_accessor :user_name, :repo_name, :description, :label, :email

  validates :repo_name, format: { with: /\A[\-\w]+\Z/, message: 'only allows letters, numbers, dashes, and underscores'}
 
  def initialize(user_name, repo_name, description=nil, label=nil)
    @user_name = user_name
    @repo_name = repo_name
    @description = description
    @label = label #TODO read this from collection.json instead of creating from scratch
  end


  def create(github_client)
    options = {
      topics: ['audiannotate'], 
      description: @label, 
      homepage: uri_root
    }
    response = github_client.create_repository(@repo_name, options)
    github_client.replace_all_topics(response.full_name, ['audiannotate'])

    github_client.create_contents(
      response.full_name, #repository full name
      'README.md', 
      'Initial creation', 
      'Repository created by AudiAnnotateWeb, version 0.0.0', # file contents
      {branch: 'gh-pages'})

    populate(github_client)
  end

  def clone(access_token)
    # due to security concerns, we shouldn't actually clone the repository but pull into an empty one
    # see https://github.blog/2012-09-21-easier-builds-and-deployments-using-git-over-https-and-oauth/
    # create a (temporary-ish) directory for the user if there isn't one
    Dir.mkdir(user_path) unless Dir.exists?(user_path)

    # create a (temporary-ish) directory for the repo if there isn't one and initialize it
    unless Dir.exists?(repo_path)
      Dir.mkdir(repo_path)
      Git.init(repo_path)
    end

    # pull into the repo, using the access token
    git = Git.open(repo_path)  # TODO consider using the logger here
    # remote = git.add_remote('origin', "https://#{access_token}@github.com/#{user_name}/#{repo_name}.git")
    git.pull("https://#{access_token}@github.com/#{user_name}/#{repo_name}.git", 'gh-pages')
  end


  def populate(github_client)
    access_token = github_client.access_token
    # eliminate conflicts with deleted repositories (rare)
    if Dir.exists?(repo_path)
      FileUtils.rm_r(repo_path)
    end

    # sync with github and set up empty directory
    clone(access_token)  # is this even needed?  TODO

    git = Git.open(repo_path)  # TODO consider using the logger here
    git.branch('gh-pages').checkout
    git.pull("https://#{access_token}@github.com/#{user_name}/#{repo_name}.git", 'gh-pages')

    # copy jekyll files
    source_paths = JEKYLL_INITIAL_FILES.map {|fn| File.join(Rails.root, '..', 'AudiAnnotateJekyllTemplate', fn)}
    FileUtils.cp_r(source_paths, repo_path)

    # remove example data
    JEKYLL_INITIAL_BLACKLIST.map{|path| File.join(repo_path, path)}.each { |path| FileUtils.rm_r(path) } 

    # write initial collection manifest
    File.write(collection_manifest_path, collection_manifest_contents)
    File.write(jekyll_config_path, jekyll_config_contents(github_client))

    # add, commit, and push
    git.add(repo_path)
    git.commit('Initial Jekyll Template')
    response = git.push("https://#{access_token}@github.com/#{user_name}/#{repo_name}.git", 'gh-pages')    
  end


  def collection_manifest_path
    File.join(repo_path, '_data', 'collection.json')
  end

  def collection_manifest_contents
    ApplicationController::render template: 'project/collection.json', layout: false, locals: {project: self}
  end

  def jekyll_config_path
    File.join(repo_path, '_config.yml')
  end

  def jekyll_config_contents(github_client)

    ApplicationController::render template: 'project/config.yml', layout: false, locals: {project: self, name: github_client.user.name}
  end

  def manifest_uri
    'https://example.com/collection.json'
  end

  def user_path
    File.join(Rails.root, 'tmp', user_name) 
  end

  def repo_path
    File.join(user_path, repo_name)
  end

  def uri_root
    "https://#{user_name}.github.io/#{repo_name}"
  end

  JEKYLL_INITIAL_FILES = %w(404.html  assets  _data  Gemfile  Gemfile.lock  _includes  index.markdown  _items  _layouts _manifests _posts .gitignore)
  JEKYLL_INITIAL_BLACKLIST = %w(_items/anne-sexton--woodberry--1974.md _data/anne-sexton--woodberry--1974)


end