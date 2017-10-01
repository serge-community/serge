package main

const welcomeMessageKey = "WelcomeMessage"

func init() {
	loc.Translations["test"] = map[string]string{
		// Localizable strings

		// H1 Heading
		welcomeMessageKey: "Ú áŕē ŵēļçőḿē!",

		// {NAME} is the name of the user
		"HelloUser": "Ĥēļļő, {ŅĀḾĒ}!",

		// {X} is the number of files, {Y} is the number of folders,
		// {COMMAND} in the ID of the command
		"XFilesFoundInYFolders": "{X_PLURAL:{X} file|{X} files} found in {Y_PLURAL:{Y} folder|{Y} folders}. Do you want to {COMMAND:copy|move|delete} {X:them|it|them}?",

		// Male name
		"John": "Ĵőĥŋ",

		// Male name, genitive case
		"John##genitive": "Ĵőĥŋ'š",

		// Single-line raw string
		"RawString": `ḟőő "ḃáŕ" ḃáž`,

		// Multi-line raw string
		"Template": `Łĩŋē 1
"Łĩŋē 2"
Łĩŋē 3`,
	}
}
