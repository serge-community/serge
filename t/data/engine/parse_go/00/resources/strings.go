package main

const welcomeMessageKey = "WelcomeMessage"

func init() {
	loc.Translations["en"] = map[string]string{
		// Localizable strings

		// H1 Heading
		welcomeMessageKey: "\u00DA are welcome!",

		// {NAME} is the name of the user
		"HelloUser": "Hello, {NAME}!",

		// {X} is the number of files, {Y} is the number of folders,
		// {COMMAND} in the ID of the command
		"XFilesFoundInYFolders": "{X_PLURAL:{X} file|{X} files} found in {Y_PLURAL:{Y} folder|{Y} folders}. Do you want to {COMMAND:copy|move|delete} {X:them|it|them}?",

		// Male name
		"John": "John",

		// Male name, genitive case
		"John##genitive": "John's",

		// Single-line raw string
		"RawString": `foo "bar" baz`,

		// Multi-line raw string
		"Template": `Line 1
"Line 2"
Line 3`,
	}
}
