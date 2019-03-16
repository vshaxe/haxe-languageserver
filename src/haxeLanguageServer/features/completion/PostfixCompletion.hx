package haxeLanguageServer.features.completion;

import haxeLanguageServer.helper.DocHelper;
import haxe.display.JsonModuleTypes;
import haxeLanguageServer.protocol.Display;
import languageServerProtocol.Types.CompletionItem;
import haxeLanguageServer.protocol.helper.DisplayPrinter;
import haxeLanguageServer.features.completion.CompletionFeature;

using Lambda;

class PostfixCompletion {
	public function new() {}

	public function createItems<TMode, TItem>(data:CompletionContextData):Array<CompletionItem> {
		var subject:FieldCompletionSubject<TItem>;
		switch (data.mode.kind) {
			case Field:
				subject = data.mode.args;
			case _:
				return [];
		}

		var type = subject.item.type;
		if (type == null) {
			return [];
		}
		var type = type.removeNulls().type;

		var range = subject.range;
		var replaceRange:Range = {
			start: range.start,
			end: data.completionPosition
		};
		var expr = data.doc.getText(range);
		if (expr.startsWith("(") && expr.endsWith(")")) {
			expr = expr.substring(1, expr.length - 1);
		}

		var items:Array<CompletionItem> = [];
		function add(item:PostfixCompletionItem) {
			items.push(createPostfixCompletionItem(item, data.doc, replaceRange));
		}

		function iterator(item:String = "item") {
			add({
				label: "for",
				detail: "for (item in expr)",
				insertText: 'for ($${1:$item} in $expr) ',
				insertTextFormat: Snippet
			});
		}
		function keyValueIterator(key:String = "key") {
			add({
				label: "for k=>v",
				detail: 'for ($key => value in expr)',
				insertText: 'for ($key => value in $expr) ',
				insertTextFormat: PlainText
			});
		}
		function indexedIterator() {
			add({
				label: "fori",
				detail: "for (i in 0...expr.length)",
				insertText: 'for (i in 0...$expr.length) ',
				insertTextFormat: PlainText
			});
		}

		var hasIteratorApi = subject.iterator != null || subject.keyValueIterator != null;

		if (subject.iterator != null) {
			iterator(subject.iterator.type.guessName());
		}
		if (subject.keyValueIterator != null) {
			keyValueIterator();
		}

		switch (type.kind) {
			case TAbstract | TInst:
				var path = type.args;
				var dotPath = new DisplayPrinter(PathPrinting.Always).printPath(path.path);
				switch (dotPath) {
					case "StdTypes.Bool":
						add({
							label: "if",
							detail: "if (expr)",
							insertText: 'if ($expr) ',
							insertTextFormat: PlainText
						});
					case "StdTypes.Int":
						add({
							label: "fori",
							detail: "for (i in 0...expr)",
							insertText: 'for (i in 0...$expr) ',
							insertTextFormat: PlainText
						});
					case "StdTypes.Float":
						add({
							label: "int",
							detail: "Std.int(expr)",
							insertText: 'Std.int($expr)',
							insertTextFormat: PlainText
						});
				}

				// TODO: remove hardcoded iterator() / keyValueIterator() handling sometime after Haxe 4 releases
				if (!hasIteratorApi) {
					switch (dotPath) {
						case "Array":
							iterator(path.params[0].guessName());
							indexedIterator();
						case "haxe.ds.Map":
							keyValueIterator();
							iterator(path.params[1].guessName());
						case "haxe.ds.List":
							keyValueIterator("index");
							iterator(path.params[0].guessName());
							indexedIterator();
					}
				}
			case _:
		}

		var switchItem = createSwitchItem(subject, expr);
		if (switchItem != null) {
			add(switchItem);
		}

		return items;
	}

	function createSwitchItem<T>(subject:FieldCompletionSubject<T>, expr:String):Null<PostfixCompletionItem> {
		var moduleType = subject.moduleType;
		if (moduleType == null) {
			return null;
		}

		// switching on a concrete enum value _works_, but it's sort of pointless
		switch (subject.item.kind) {
			case EnumField:
				return null;
			case EnumAbstractField:
				return null;
			case _:
		}

		function make(print:(snippets:Bool) -> String):PostfixCompletionItem {
			return {
				label: "switch",
				detail: "switch (expr) {cases...}",
				insertText: print(true),
				insertTextFormat: Snippet,
				code: print(false)
			};
		}

		var printer = new DisplayPrinter();
		switch (moduleType.kind) {
			case Enum:
				var e:JsonEnum = moduleType.args;
				if (e.constructors.length > 0) {
					return make(printer.printSwitchOnEnum.bind(expr, e));
				}
			case Abstract if (moduleType.meta.hasMeta(Enum)):
				var a:JsonAbstract = moduleType.args;
				if (a.impl != null && a.impl.statics.exists(Helper.isEnumAbstractField)) {
					return make(printer.printSwitchOnEnumAbstract.bind(expr, a));
				}
			case _:
		}
		return null;
	}

	function createPostfixCompletionItem(data:PostfixCompletionItem, doc:TextDocument, replaceRange:Range):CompletionItem {
		var item:CompletionItem = {
			label: data.label,
			detail: data.detail,
			sortText: data.sortText,
			filterText: doc.getText(replaceRange) + " " + data.label, // https://github.com/Microsoft/vscode/issues/38982
			kind: Snippet,
			insertTextFormat: data.insertTextFormat,
			textEdit: {
				newText: data.insertText,
				range: replaceRange
			},
			data: {
				origin: CompletionItemOrigin.Custom
			}
		}

		if (data.code != null) {
			item.documentation = {
				kind: MarkDown,
				value: DocHelper.printCodeBlock(data.code, Haxe)
			}
		}

		return item;
	}
}

private typedef PostfixCompletionItem = {
	var label:String;
	var detail:String;
	var insertText:String;
	var insertTextFormat:InsertTextFormat;
	var ?code:String;
	var ?sortText:String;
}
