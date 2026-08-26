note
	description: "[
		The one authoritative version mark, shown in the title bar
		and the About dialog so the running build is always
		checkable at a glance. Keep in step with
		installer/simple_ocr_capture.iss (AppVersion) and
		CHANGELOG.md at every release.
	]"

class
	OCR_VERSION

feature -- Access

	Version: STRING = "1.11.0"
			-- The released version this build carries.

	Built: STRING = "2026-08-26"
			-- The day this version was finalized.

end
