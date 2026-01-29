class DocumentationController < ApplicationController
  def show
    @organization = Current.organization
  end
end
