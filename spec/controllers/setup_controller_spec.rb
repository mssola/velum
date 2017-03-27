# frozen_string_literal: true
require "rails_helper"

# rubocop:disable RSpec/AnyInstance
RSpec.describe SetupController, type: :controller do
  let(:user)   { create(:user)   }
  let(:minion) { create(:minion) }

  describe "GET /" do
    it "gets redirected if not logged in" do
      get :welcome
      expect(response.status).to eq 302
    end

    context "HTML rendering" do
      it "returns a 200 if logged in" do
        sign_in user

        get :welcome
        expect(response.status).to eq 200
      end

      it "renders with HTML if no format was specified" do
        sign_in user

        get :welcome
        expect(response["Content-Type"].include?("text/html")).to be true
      end
    end
  end

  describe "POST /setup/bootstrap via HTML" do
    let(:salt) { Velum::Salt }
    before do
      sign_in user
      Minion.create! [{ hostname: "master" }, { hostname: "minion0" }]
    end

    context "when the minion doesn't exist" do
      it "renders an error with not_found" do
        post :bootstrap, roles: { master: 9999999 }
        expect(flash[:error]).to be_present
        expect(response.redirect_url).to eq "http://test.host/setup"
      end
    end

    context "when the user successfully chooses the master" do
      before do
        [:minion, :master].each do |role|
          allow_any_instance_of(Velum::SaltMinion).to receive(:assign_role).with(role)
            .and_return(role)
        end
        allow(salt).to receive(:orchestrate)
      end

      it "sets the master" do
        post :bootstrap, roles: { master: Minion.first.id, minion: Minion.all[1..-1].map(&:id) }
        # check that all minions are set to minion role
        expect(Minion.first.role).to eq "master"
      end

      it "sets the other roles to minions" do
        post :bootstrap, roles: { master: Minion.first.id, minion: Minion.all[1..-1].map(&:id) }
        # check that all minions are set to minion role
        expect(Minion.where("hostname REGEXP ?", "minion*").map(&:role).uniq).to eq ["minion"]
      end

      it "calls the orchestration" do
        post :bootstrap, roles: { master: Minion.first.id, minion: Minion.all[1..-1].map(&:id) }
        expect(salt).to have_received(:orchestrate)
      end

      it "gets redirected to the list of nodes" do
        post :bootstrap, roles: { master: Minion.first.id, minion: Minion.all[1..-1].map(&:id) }
        expect(response.redirect_url).to eq "http://test.host/"
        expect(response.status).to eq 302
      end
    end

    context "when the user fails to choose the master" do
      before do
        [:minion, :master].each do |role|
          allow_any_instance_of(Velum::SaltMinion).to receive(:assign_role).with(role)
            .and_return(false)
        end
        allow(salt).to receive(:orchestrate)
      end

      it "gets redirected to the discovery page" do
        post :bootstrap, roles: { master: Minion.first.id, minion: Minion.all[1..-1].map(&:id) }
        expect(flash[:error]).to be_present
        expect(response.redirect_url).to eq "http://test.host/setup/discovery"
      end

      it "doesn't call the orchestration" do
        post :bootstrap, roles: { master: Minion.first.id, minion: Minion.all[1..-1].map(&:id) }
        expect(Velum::Salt).to have_received(:orchestrate).exactly(0).times
      end
    end
  end

  describe "POST /setup/bootstrap via JSON" do
    let(:salt) { Velum::Salt }
    before do
      sign_in user
      Minion.create! [{ hostname: "master" }, { hostname: "minion0" }]
      request.accept = "application/json"
    end

    context "when the minion doesn't exist" do
      it "renders an error with not_found" do
        post :bootstrap, roles: { master: 9999999 }
        expect(response).to have_http_status(:not_found)
      end
    end

    context "when the user successfully chooses the master" do
      before do
        [:minion, :master].each do |role|
          allow_any_instance_of(Velum::SaltMinion).to receive(:assign_role).with(role)
            .and_return(role)
        end
        allow(salt).to receive(:orchestrate)
      end

      it "sets the master" do
        post :bootstrap, roles: { master: Minion.first.id, minion: Minion.all[1..-1].map(&:id) }
        # check that all minions are set to minion role
        expect(Minion.first.role).to eq "master"
      end

      it "sets the other roles to minions" do
        post :bootstrap, roles: { master: Minion.first.id, minion: Minion.all[1..-1].map(&:id) }
        # check that all minions are set to minion role
        expect(Minion.where("hostname REGEXP ?", "minion*").map(&:role).uniq).to eq ["minion"]
      end

      it "calls the orchestration" do
        post :bootstrap, roles: { master: Minion.first.id, minion: Minion.all[1..-1].map(&:id) }
        expect(salt).to have_received(:orchestrate)
      end
    end

    context "when the user fails to choose the master" do
      before do
        [:minion, :master].each do |role|
          allow_any_instance_of(Velum::SaltMinion).to receive(:assign_role).with(role)
            .and_return(false)
        end
        allow(salt).to receive(:orchestrate)
      end

      it "returns unprocessable entity" do
        post :bootstrap, roles: { master: Minion.first.id, minion: Minion.all[1..-1].map(&:id) }
        expect(response).to have_http_status(:unprocessable_entity)
      end

      it "doesn't call the orchestration" do
        post :bootstrap, roles: { master: Minion.first.id, minion: Minion.all[1..-1].map(&:id) }
        expect(Velum::Salt).to have_received(:orchestrate).exactly(0).times
      end
    end
  end

  describe "PUT /setup via HTML" do
    let(:settings_params) do
      {
        company_name: "SUSE Linux GmbH",
        company_unit: "Research and development",
        email:        "containers@suse.de",
        country:      "DE",
        state:        "Bavaria",
        city:         "Nuremberg"
      }
    end

    it 'assigns the Pillar "dashboard" to the host of the request automatically' do
      sign_in user
      put :configure, settings: settings_params
      expect(Pillar.find_by(pillar: "dashboard").value).to eq("test.host")
    end

    context "when the user configures the cluster successfully" do
      before do
        sign_in user
        allow_any_instance_of(Pillar).to receive(:save).and_return(true)
      end

      it "gets redirected to the setup_worker_bootstrap_path" do
        put :configure, settings: settings_params
        expect(response.redirect_url).to eq "http://test.host/setup/worker-bootstrap"
        expect(response.status).to eq 302
      end
    end

    context "when the user fails to configure the cluster" do
      before do
        sign_in user
        allow_any_instance_of(Pillar).to receive(:save).and_return(false)
      end

      it "gets redirected to the setup_worker_bootstrap_path with an error" do
        put :configure, settings: settings_params
        expect(flash[:alert]).to be_present
        expect(response.redirect_url).to eq "http://test.host/setup/worker-bootstrap"
      end
    end

    context "when the user doesn't specify any values" do
      before do
        sign_in user
      end

      it "warns and redirects to the setup_path" do
        put :configure, settings: settings_params.each { |k, _v| settings_params[k] = "" }
        expect(flash[:alert]).to be_present
        expect(response.redirect_url).to eq "http://test.host/setup"
      end
    end
  end

  describe "PUT /setup via JSON" do
    let(:settings_params) do
      {
        company_name: "SUSE Linux GmbH",
        company_unit: "Research and development",
        email:        "containers@suse.de",
        country:      "DE",
        state:        "Bavaria",
        city:         "Nuremberg"
      }
    end

    context "when the user configures the cluster successfully" do
      before do
        sign_in user
        allow_any_instance_of(Pillar).to receive(:save).and_return(true)
        request.accept = "application/json"
      end

      it "returns with 200" do
        put :configure, settings: settings_params
        expect(response).to have_http_status(:ok)
      end
    end

    context "when the user fails to configure the cluster" do
      before do
        sign_in user
        allow_any_instance_of(Pillar).to receive(:save).and_return(false)
        request.accept = "application/json"
      end

      it "returns unprocessable entity" do
        put :configure, settings: settings_params
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context "when the user doesn't specify any values" do
      before do
        sign_in user
        request.accept = "application/json"
      end

      it "returns unprocessable entity" do
        put :configure, settings: settings_params.each { |k, _v| settings_params[k] = "" }
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe "GET /setup/discovery" do
    before do
      sign_in user
      allow_any_instance_of(SetupController).to receive(:redirect_to_dashboard)
        .and_return(true)
    end

    it "shows the minions" do
      get :discovery
      expect(response.status).to eq 200
    end
  end
end
# rubocop:enable RSpec/AnyInstance