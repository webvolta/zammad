require 'rails_helper'

RSpec.describe 'System > Translations', type: :system do
  prepend_before do
    Locale.where.not(locale: %w[en-us de-de]).destroy_all # remove all but 2 locales for quicker test
  end

  it 'when clicking "Get latest translations" fetches all translations' do
    visit 'system/translation'

    expect(Translation).to receive(:load).with('de-de').and_return(true)
    expect(Translation).to receive(:load).with('en-us').and_return(true)

    click '.js-syncChanges'

    modal_ready && modal_disappear # make sure test is not terminated while modal is visible
  end
end
