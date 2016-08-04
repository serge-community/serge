This test uses `leave_untranslated_blank YES` setting and then cleans up untranslated strings
from final localized resource files, thus removing the size of resources and allowing Android
to use its own fallback scheme.

This kind of setup is useful when using source language other than English,
but the application still needs to fall back to English strings.