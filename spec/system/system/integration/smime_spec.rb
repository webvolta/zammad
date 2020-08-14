require 'rails_helper'

RSpec.describe 'Manage > Integration > S/MIME', type: :system do

  let(:fixture) { 'smime1@example.com' }

  let!(:certificate) do
    File.read(Rails.root.join("spec/fixtures/smime/#{fixture}.crt"))
  end
  let!(:private_key) do
    File.read(Rails.root.join("spec/fixtures/smime/#{fixture}.key"))
  end
  let!(:private_key_secret) do
    File.read(Rails.root.join("spec/fixtures/smime/#{fixture}.secret")).strip
  end

  it 'enabling and adding of public and private key' do
    visit 'system/integration/smime'

    # enable S/MIME
    click 'label[for=setting-switch]'

    # add cert
    click '.js-addCertificate'
    fill_in 'Paste Certificate', with: certificate
    click '.js-submit'

    # add private key
    click '.js-addPrivateKey'
    fill_in 'Paste Private Key', with: private_key
    fill_in 'Enter Private Key secret', with: private_key_secret
    click '.js-submit'

    # wait for ajax
    expect(page).to have_css('td', text: 'Including private key')

    # check result
    expect( Setting.get('smime_integration') ).to be true
    expect( SMIMECertificate.last.fingerprint ).to be_present
    expect( SMIMECertificate.last.raw ).to be_present
    expect( SMIMECertificate.last.private_key ).to be_present
  end
end
