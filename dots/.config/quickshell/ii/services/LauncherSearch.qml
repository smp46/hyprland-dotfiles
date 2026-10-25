pragma Singleton

import qs.modules.common
import qs.modules.common.models
import qs.modules.common.functions
import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

Singleton {
    id: root

    property string query: ""

    function ensurePrefix(prefix) {
        if ([Config.options.search.prefix.action, Config.options.search.prefix.app, Config.options.search.prefix.clipboard, Config.options.search.prefix.emojis, Config.options.search.prefix.math, Config.options.search.prefix.shellCommand, Config.options.search.prefix.webSearch, Config.options.search.prefix.file ?? "~"].some(i => root.query.startsWith(i))) {
            root.query = prefix + root.query.slice(1);
        } else {
            root.query = prefix + root.query;
        }
    }

    function cleanFileQuery(raw) {
        let q = raw.trim();
        let pfx = Config.options.search.prefix.file ?? "~";
        if (q.startsWith("~/")) q = q.slice(2);
        else if (q.startsWith(pfx)) q = q.slice(pfx.length);
        return q.trim();
    }

    function cleanWebQuery(raw) {
        let q = raw.trim();
        let pfx = Config.options.search.prefix.webSearch ?? "?";
        return StringUtils.cleanPrefix(q, pfx).trim();
    }

    // https://specifications.freedesktop.org/menu/latest/category-registry.html
    property list<string> mainRegisteredCategories: ["AudioVideo", "Development", "Education", "Game", "Graphics", "Network", "Office", "Science", "Settings", "System", "Utility"]
    property list<string> appCategories: DesktopEntries.applications.values.reduce((acc, entry) => {
        for (const category of entry.categories) {
            if (!acc.includes(category) && mainRegisteredCategories.includes(category)) {
                acc.push(category);
            }
        }
        return acc;
    }, []).sort()

    // Load user action scripts from ~/.config/illogical-impulse/actions/
    // Uses FolderListModel to auto-reload when scripts are added/removed
    property var userActionScripts: {
        const actions = [];
        for (let i = 0; i < userActionsFolder.count; i++) {
            const fileName = userActionsFolder.get(i, "fileName");
            const filePath = userActionsFolder.get(i, "filePath");
            if (fileName && filePath) {
                const actionName = fileName.replace(/\.[^/.]+$/, ""); // strip extension
                actions.push({
                    action: actionName,
                    execute: ((path) => (args) => {
                        Quickshell.execDetached([path, ...(args ? args.split(" ") : [])]);
                    })(FileUtils.trimFileProtocol(filePath.toString()))
                });
            }
        }
        return actions;
    }

    FolderListModel {
        id: userActionsFolder
        folder: Qt.resolvedUrl(Directories.userActions)
        showDirs: false
        showHidden: false
        sortField: FolderListModel.Name
    }

    property var searchActions: [
        {
            action: "accentcolor",
            execute: args => {
                Quickshell.execDetached([Directories.wallpaperSwitchScriptPath, "--noswitch", "--color", ...(args != '' ? [`${args}`] : [])]);
            }
        },
        {
            action: "dark",
            execute: () => {
                Quickshell.execDetached([Directories.wallpaperSwitchScriptPath, "--mode", "dark", "--noswitch"]);
            }
        },
        {
            action: "konachanwallpaper",
            execute: () => {
                Quickshell.execDetached([Quickshell.shellPath("scripts/colors/random/random_konachan_wall.sh")]);
            }
        },
        {
            action: "light",
            execute: () => {
                Quickshell.execDetached([Directories.wallpaperSwitchScriptPath, "--mode", "light", "--noswitch"]);
            }
        },
        {
            action: "superpaste",
            execute: args => {
                if (!/^(\d+)/.test(args.trim())) {
                    // Invalid if doesn't start with numbers
                    Quickshell.execDetached(["notify-send", Translation.tr("Superpaste"), Translation.tr("Usage: <tt>%1superpaste NUM_OF_ENTRIES[i]</tt>\nSupply <tt>i</tt> when you want images\nExamples:\n<tt>%1superpaste 4i</tt> for the last 4 images\n<tt>%1superpaste 7</tt> for the last 7 entries").arg(Config.options.search.prefix.action), "-a", "Shell"]);
                    return;
                }
                const syntaxMatch = /^(?:(\d+)(i)?)/.exec(args.trim());
                const count = syntaxMatch[1] ? parseInt(syntaxMatch[1]) : 1;
                const isImage = !!syntaxMatch[2];
                Cliphist.superpaste(count, isImage);
            }
        },
        {
            action: "todo",
            execute: args => {
                Todo.addTask(args);
            }
        },
        {
            action: "wallpaper",
            execute: () => {
                Hyprland.dispatch(`hl.dsp.global("quickshell:wallpaperSelectorToggle")`)
            }
        },
        {
            action: "wipeclipboard",
            execute: () => {
                Cliphist.wipe();
            }
        },
    ]

    // Combined built-in and user actions
    property var allActions: searchActions.concat(userActionScripts)

    property string mathResult: ""
    property bool clipboardWorkSafetyActive: {
        const enabled = Config.options.workSafety.enable.clipboard;
        const sensitiveNetwork = (StringUtils.stringListContainsSubstring(Network.networkName.toLowerCase(), Config.options.workSafety.triggerCondition.networkNameKeywords));
        return enabled && sensitiveNetwork;
    }

    function containsUnsafeLink(entry) {
        if (entry == undefined)
            return false;
        const unsafeKeywords = Config.options.workSafety.triggerCondition.linkKeywords;
        return StringUtils.stringListContainsSubstring(entry.toLowerCase(), unsafeKeywords);
    }

    property var rawFileResults: []
    property var rawKagiResults: []
    property string lastFileQuery: ""
    property string lastKagiQuery: ""
    property string lastMathQuery: ""

    onQueryChanged: {
        let q = root.query.trim();
        if (q === "") {
            root.mathResult = "";
            root.rawFileResults = [];
            root.rawKagiResults = [];
            root.lastFileQuery = "";
            root.lastKagiQuery = "";
            root.lastMathQuery = "";
            mathProc.running = false;
            fileSearchProc.running = false;
            kagiSearchProc.running = false;
            nonAppResultsTimer.stop();
        } else {
            let filePrefix = Config.options.search.prefix.file ?? "~";
            if (q === filePrefix || q === "~/") {
                nonAppResultsTimer.stop();
                root.triggerNonAppSearch();
            } else {
                nonAppResultsTimer.restart();
            }
        }
    }

    function triggerNonAppSearch() {
        let q = root.query.trim();
        if (q === "") return;

        // Math
        let expr = q;
        if (expr.startsWith(Config.options.search.prefix.math)) {
            expr = expr.slice(Config.options.search.prefix.math.length).trim();
        }
        if (expr !== "" && (q.startsWith(Config.options.search.prefix.math) || /^\d/.test(q))) {
            if (expr !== root.lastMathQuery) {
                root.lastMathQuery = expr;
                mathProc.calculateExpression(expr);
            }
        } else {
            root.mathResult = "";
            root.lastMathQuery = "";
        }

        // File search
        let cleanFile = root.cleanFileQuery(q);
        let filePrefix = Config.options.search.prefix.file ?? "~";
        let isFileSearch = q.startsWith(filePrefix) || q.startsWith("~/") || q.startsWith("/");
        if (isFileSearch || cleanFile.length >= 2) {
            let fileKey = (isFileSearch ? "F:" : "G:") + cleanFile;
            if (fileKey !== root.lastFileQuery) {
                root.lastFileQuery = fileKey;
                fileSearchProc.search(cleanFile, isFileSearch ? 15 : 5);
            }
        } else {
            root.rawFileResults = [];
            root.lastFileQuery = "";
        }

        // Kagi web search
        let webPrefix = Config.options.search.prefix.webSearch ?? "?";
        let isWebSearch = q.startsWith(webPrefix);
        let cleanWeb = root.cleanWebQuery(q);
        let allowDefaultWeb = Config.options.search.prefix.showDefaultActionsWithoutPrefix && !isFileSearch && !q.startsWith(Config.options.search.prefix.action) && !q.startsWith(Config.options.search.prefix.app) && !q.startsWith(Config.options.search.prefix.clipboard) && !q.startsWith(Config.options.search.prefix.emojis) && !q.startsWith(Config.options.search.prefix.math) && !q.startsWith(Config.options.search.prefix.shellCommand);
        if ((isWebSearch && cleanWeb.length >= 1) || (allowDefaultWeb && cleanWeb.length >= 2)) {
            if (cleanWeb !== root.lastKagiQuery) {
                root.lastKagiQuery = cleanWeb;
                kagiSearchProc.search(cleanWeb);
            }
        } else if (!isWebSearch && !allowDefaultWeb) {
            root.rawKagiResults = [];
            root.lastKagiQuery = "";
        } else if (cleanWeb.length === 0) {
            root.rawKagiResults = [];
            root.lastKagiQuery = "";
        }
    }

    Timer {
        id: nonAppResultsTimer
        interval: Config.options.search.nonAppResultDelay ?? 30
        repeat: false
        onTriggered: root.triggerNonAppSearch()
    }

    Process {
        id: mathProc
        property list<string> baseCommand: ["qalc", "-t"]
        function calculateExpression(expression) {
            mathProc.running = false;
            mathProc.command = baseCommand.concat(expression);
            mathProc.running = true;
        }
        stdout: SplitParser {
            onRead: data => {
                root.mathResult = data;
            }
        }
    }

    Process {
        id: fileSearchProc
        property string queryTarget: ""
        property int maxCountTarget: 15
        property string pendingQuery: ""
        property int pendingMaxCount: 15
        property bool hasPending: false
        stdout: StdioCollector {
            onStreamFinished: {
                let txt = text ? text.trim() : "";
                if (txt.length > 0 && fileSearchProc.queryTarget === root.cleanFileQuery(root.query)) {
                    try {
                        root.rawFileResults = JSON.parse(txt);
                    } catch(e) {
                        root.rawFileResults = [];
                    }
                }
            }
        }
        onRunningChanged: {
            if (!fileSearchProc.running && fileSearchProc.hasPending) {
                let pq = fileSearchProc.pendingQuery;
                let pm = fileSearchProc.pendingMaxCount;
                fileSearchProc.hasPending = false;
                fileSearchProc.queryTarget = pq;
                fileSearchProc.maxCountTarget = pm;
                fileSearchProc.command = [
                    "python3",
                    "-S",
                    Quickshell.shellPath("scripts/search/filesearch.py"),
                    pq,
                    String(pm || 15)
                ];
                fileSearchProc.running = true;
            }
        }
        function search(searchQuery, maxCount) {
            if (fileSearchProc.running) {
                fileSearchProc.pendingQuery = searchQuery;
                fileSearchProc.pendingMaxCount = maxCount || 15;
                fileSearchProc.hasPending = true;
                fileSearchProc.running = false;
            } else {
                fileSearchProc.hasPending = false;
                fileSearchProc.queryTarget = searchQuery;
                fileSearchProc.maxCountTarget = maxCount || 15;
                fileSearchProc.command = [
                    "python3",
                    "-S",
                    Quickshell.shellPath("scripts/search/filesearch.py"),
                    searchQuery,
                    String(maxCount || 15)
                ];
                fileSearchProc.running = true;
            }
        }
    }

    Process {
        id: kagiSearchProc
        property string queryTarget: ""
        property string pendingQuery: ""
        property bool hasPending: false
        stdout: StdioCollector {
            onStreamFinished: {
                let txt = text ? text.trim() : "";
                if (txt.length > 0 && kagiSearchProc.queryTarget === root.cleanWebQuery(root.query)) {
                    try {
                        root.rawKagiResults = JSON.parse(txt);
                    } catch(e) {
                        root.rawKagiResults = [];
                    }
                }
            }
        }
        onRunningChanged: {
            if (!kagiSearchProc.running && kagiSearchProc.hasPending) {
                let pq = kagiSearchProc.pendingQuery;
                kagiSearchProc.hasPending = false;
                kagiSearchProc.queryTarget = pq;
                let token = Config.options.search.kagiToken || "";
                kagiSearchProc.command = [
                    "python3",
                    "-S",
                    Quickshell.shellPath("scripts/search/kagisearch.py"),
                    pq,
                    token
                ];
                kagiSearchProc.running = true;
            }
        }
        function search(searchQuery) {
            if (kagiSearchProc.running) {
                kagiSearchProc.pendingQuery = searchQuery;
                kagiSearchProc.hasPending = true;
                kagiSearchProc.running = false;
            } else {
                kagiSearchProc.hasPending = false;
                kagiSearchProc.queryTarget = searchQuery;
                let token = Config.options.search.kagiToken || "";
                kagiSearchProc.command = [
                    "python3",
                    "-S",
                    Quickshell.shellPath("scripts/search/kagisearch.py"),
                    searchQuery,
                    token
                ];
                kagiSearchProc.running = true;
            }
        }
    }

    property list<var> results: {
        // Search results are handled here
        ////////////////// Skip? //////////////////
        if (root.query == "")
            return [];

        ///////////// Special cases ///////////////
        if (root.query.startsWith(Config.options.search.prefix.clipboard)) {
            // Clipboard
            const searchString = StringUtils.cleanPrefix(root.query, Config.options.search.prefix.clipboard);
            return Cliphist.fuzzyQuery(searchString).map((entry, index, array) => {
                const mightBlurImage = Cliphist.entryIsImage(entry) && root.clipboardWorkSafetyActive;
                let shouldBlurImage = mightBlurImage;
                if (mightBlurImage) {
                    shouldBlurImage = shouldBlurImage && (root.containsUnsafeLink(array[index - 1]) || root.containsUnsafeLink(array[index + 1]));
                }
                const type = `#${entry.match(/^\s*(\S+)/)?.[1] || ""}`;
                return resultComp.createObject(null, {
                    rawValue: entry,
                    name: StringUtils.cleanCliphistEntry(entry),
                    verb: "",
                    type: type,
                    execute: () => {
                        Cliphist.copy(entry);
                    },
                    actions: [resultComp.createObject(null, {
                            name: Translation.tr("Copy"),
                            iconName: "content_copy",
                            iconType: LauncherSearchResult.IconType.Material,
                            execute: () => {
                                Cliphist.copy(entry);
                            }
                        }), resultComp.createObject(null, {
                            name: Translation.tr("Delete"),
                            iconName: "delete",
                            iconType: LauncherSearchResult.IconType.Material,
                            execute: () => {
                                Cliphist.deleteEntry(entry);
                            }
                        })],
                    blurImage: shouldBlurImage
                });
            }).filter(Boolean);
        } else if (root.query.startsWith(Config.options.search.prefix.emojis)) {
            // Clipboard
            const searchString = StringUtils.cleanPrefix(root.query, Config.options.search.prefix.emojis);
            return Emojis.fuzzyQuery(searchString).map(entry => {
                const emoji = entry.match(/^\s*(\S+)/)?.[1] || "";
                return resultComp.createObject(null, {
                    rawValue: entry,
                    name: entry.replace(/^\s*\S+\s+/, ""),
                    iconName: emoji,
                    iconType: LauncherSearchResult.IconType.Text,
                    verb: Translation.tr("Copy"),
                    type: Translation.tr("Emoji"),
                    execute: () => {
                        Quickshell.clipboardText = entry.match(/^\s*(\S+)/)?.[1];
                    }
                });
            }).filter(Boolean);
        }

        ////////////////// Init ///////////////////
        const mathResultObject = resultComp.createObject(null, {
            name: root.mathResult,
            verb: Translation.tr("Copy"),
            type: Translation.tr("Math result"),
            fontType: LauncherSearchResult.FontType.Monospace,
            iconName: 'calculate',
            iconType: LauncherSearchResult.IconType.Material,
            execute: () => {
                Quickshell.clipboardText = root.mathResult;
            }
        });
        const appResultObjects = AppSearch.fuzzyQuery(StringUtils.cleanPrefix(root.query, Config.options.search.prefix.app)).map(entry => {
            return resultComp.createObject(null, {
                type: Translation.tr("App"),
                id: entry.id,
                name: entry.name,
                iconName: entry.icon,
                iconType: LauncherSearchResult.IconType.System,
                verb: Translation.tr("Open"),
                execute: () => {
                    if (!entry.runInTerminal)
                        entry.execute();
                    else {
                        // Probably needs more proper escaping, but this will do for now
                        Quickshell.execDetached(["bash", '-c', `${Config.options.apps.terminal} -e '${StringUtils.shellSingleQuoteEscape(entry.command.join(' '))}'`]);
                    }
                },
                comment: entry.comment,
                runInTerminal: entry.runInTerminal,
                genericName: entry.genericName,
                keywords: entry.keywords,
                actions: entry.actions.map(action => {
                    return resultComp.createObject(null, {
                        name: action.name,
                        iconName: action.icon,
                        iconType: LauncherSearchResult.IconType.System,
                        execute: () => {
                            if (!action.runInTerminal)
                                action.execute();
                            else {
                                Quickshell.execDetached(["bash", '-c', `${Config.options.apps.terminal} -e '${StringUtils.shellSingleQuoteEscape(action.command.join(' '))}'`]);
                            }
                        }
                    });
                })
            });
        });
        const commandResultObject = resultComp.createObject(null, {
            name: StringUtils.cleanPrefix(root.query, Config.options.search.prefix.shellCommand).replace("file://", ""),
            verb: Translation.tr("Run"),
            type: Translation.tr("Command"),
            fontType: LauncherSearchResult.FontType.Monospace,
            iconName: 'terminal',
            iconType: LauncherSearchResult.IconType.Material,
            execute: () => {
                let cleanedCommand = root.query.replace("file://", "");
                cleanedCommand = StringUtils.cleanPrefix(cleanedCommand, Config.options.search.prefix.shellCommand);
                if (cleanedCommand.startsWith(Config.options.search.prefix.shellCommand)) {
                    cleanedCommand = cleanedCommand.slice(Config.options.search.prefix.shellCommand.length);
                }
                Quickshell.execDetached(["bash", "-c", root.query.startsWith('sudo') ? `${Config.options.apps.terminal} fish -C '${cleanedCommand}'` : cleanedCommand]);
            }
        });
        const fileResultObjects = (root.rawFileResults || []).map(file => {
            return resultComp.createObject(null, {
                name: file.name,
                rawValue: file.path,
                type: file.dir,
                verb: Translation.tr("Open"),
                iconName: file.icon,
                iconType: LauncherSearchResult.IconType.Material,
                execute: () => {
                    Quickshell.execDetached(["xdg-open", file.path]);
                },
                actions: [
                    resultComp.createObject(null, {
                        name: Translation.tr("Open Containing Folder"),
                        iconName: "folder_open",
                        iconType: LauncherSearchResult.IconType.Material,
                        execute: () => {
                            Quickshell.execDetached(["dolphin", "--select", file.path]);
                        }
                    }),
                    resultComp.createObject(null, {
                        name: Translation.tr("Copy Path"),
                        iconName: "content_copy",
                        iconType: LauncherSearchResult.IconType.Material,
                        execute: () => {
                            Quickshell.clipboardText = file.path;
                        }
                    }),
                    resultComp.createObject(null, {
                        name: Translation.tr("Open in Terminal"),
                        iconName: "terminal",
                        iconType: LauncherSearchResult.IconType.Material,
                        execute: () => {
                            let dir = file.isDir ? file.path : FileUtils.parentDirectory(file.path);
                            Quickshell.execDetached(["kitty", "-1", "--directory", dir]);
                        }
                    })
                ]
            });
        });

        const cleanWeb = root.cleanWebQuery(root.query);
        const webSearchResultObject = resultComp.createObject(null, {
            name: cleanWeb,
            verb: Translation.tr("Search"),
            type: Translation.tr("Search Kagi"),
            iconName: 'travel_explore',
            iconType: LauncherSearchResult.IconType.Material,
            execute: () => {
                let url = Config.options.search.engineBaseUrl + encodeURIComponent(cleanWeb);
                Quickshell.execDetached(["firefox", "-P", "personal", url]);
            },
            actions: [
                resultComp.createObject(null, {
                    name: Translation.tr("Open in New Tab"),
                    iconName: "open_in_new",
                    iconType: LauncherSearchResult.IconType.Material,
                    execute: () => {
                        let url = Config.options.search.engineBaseUrl + encodeURIComponent(cleanWeb);
                        Quickshell.execDetached(["firefox", "-P", "personal", url]);
                    }
                }),
                resultComp.createObject(null, {
                    name: Translation.tr("Copy URL"),
                    iconName: "content_copy",
                    iconType: LauncherSearchResult.IconType.Material,
                    execute: () => {
                        let url = Config.options.search.engineBaseUrl + encodeURIComponent(cleanWeb);
                        Quickshell.clipboardText = url;
                    }
                })
            ]
        });

        const kagiResultObjects = (root.rawKagiResults || []).map(item => {
            const isDirectResult = item.type === "result";
            return resultComp.createObject(null, {
                name: item.title,
                rawValue: item.url,
                comment: item.snippet || "",
                verb: isDirectResult ? Translation.tr("Open") : Translation.tr("Search"),
                type: isDirectResult ? (item.domain || "Web") : "Kagi suggestion",
                iconName: 'travel_explore',
                iconType: LauncherSearchResult.IconType.Material,
                execute: () => {
                    Quickshell.execDetached(["firefox", "-P", "personal", item.url]);
                },
                actions: [
                    resultComp.createObject(null, {
                        name: Translation.tr("Open in New Tab"),
                        iconName: "open_in_new",
                        iconType: LauncherSearchResult.IconType.Material,
                        execute: () => {
                            Quickshell.execDetached(["firefox", "-P", "personal", item.url]);
                        }
                    }),
                    resultComp.createObject(null, {
                        name: Translation.tr("Copy Link"),
                        iconName: "content_copy",
                        iconType: LauncherSearchResult.IconType.Material,
                        execute: () => {
                            Quickshell.clipboardText = item.url;
                        }
                    })
                ]
            });
        });

        const launcherActionObjects = root.allActions.map(action => {
            const actionString = `${Config.options.search.prefix.action}${action.action}`;
            if (actionString.startsWith(root.query) || root.query.startsWith(actionString)) {
                return resultComp.createObject(null, {
                    name: root.query.startsWith(actionString) ? root.query : actionString,
                    verb: Translation.tr("Run"),
                    type: Translation.tr("Action"),
                    iconName: 'settings_suggest',
                    iconType: LauncherSearchResult.IconType.Material,
                    execute: () => {
                        action.execute(root.query.split(" ").slice(1).join(" "));
                    }
                });
            }
            return null;
        }).filter(Boolean);

        //////// Prioritized by prefix /////////
        let result = [];
        const startsWithNumber = /^\d/.test(root.query);
        const startsWithMathPrefix = root.query.startsWith(Config.options.search.prefix.math);
        const startsWithShellCommandPrefix = root.query.startsWith(Config.options.search.prefix.shellCommand);
        const startsWithWebSearchPrefix = root.query.startsWith(Config.options.search.prefix.webSearch);
        const filePrefix = Config.options.search.prefix.file ?? "~";
        const startsWithFilePrefix = root.query.startsWith(filePrefix) || root.query.startsWith("~/") || root.query.startsWith("/");

        if (startsWithFilePrefix) {
            return fileResultObjects;
        }

        if (startsWithNumber || startsWithMathPrefix) {
            result.push(mathResultObject);
        } else if (startsWithShellCommandPrefix) {
            result.push(commandResultObject);
        } else if (startsWithWebSearchPrefix) {
            result.push(webSearchResultObject);
            result = result.concat(kagiResultObjects);
            return result;
        }

        //////////////// Apps //////////////////
        result = result.concat(appResultObjects);

        ////////// Launcher actions ////////////
        result = result.concat(launcherActionObjects);

        ////////////// Files ///////////////////
        if (fileResultObjects.length > 0) {
            result = result.concat(fileResultObjects.slice(0, 5));
        }

        /// Math result, command, web search ///
        if (Config.options.search.prefix.showDefaultActionsWithoutPrefix) {
            if (!startsWithShellCommandPrefix)
                result.push(commandResultObject);
            if (!startsWithNumber && !startsWithMathPrefix)
                result.push(mathResultObject);
            if (!startsWithWebSearchPrefix) {
                result.push(webSearchResultObject);
                if (kagiResultObjects.length > 0) {
                    result = result.concat(kagiResultObjects.slice(0, 3));
                }
            }
        }

        return result;
    }

    Component {
        id: resultComp
        LauncherSearchResult {}
    }
}
