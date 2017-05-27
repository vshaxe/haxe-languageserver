package haxeLanguageServer.hxParser;

import haxeLanguageServer.TextDocument;

class LocalUsageResolverTest extends TestCaseBase {
    function check(code:String) {
        var expectedUsages = findMarkedRanges(code, "%");
        var declaration = expectedUsages[0];

        code = code.replace("%", "");

        var resolver = new LocalUsageResolver(declaration);
        resolver.walkFile(new TextDocument(new DocumentUri("file:///c:/"), "haxe", 0, code).parseTree, Root);
        var actualUsages = resolver.usages;

        function fail() {
            throw 'Expected $expectedUsages but was $actualUsages';
        }

        if (expectedUsages.length != actualUsages.length) {
            fail();
        } else {
            for (i in 0...expectedUsages.length) {
                if (!expectedUsages[i].isEqual(actualUsages[i])) {
                    fail();
                }
            }
        }
        currentTest.done = true;
    }

    function findMarkedRanges(code:String, marker:String):Array<Range> {
        // not expecting multiple marked words in a single line..
        var lineNumber = 0;
        var ranges = [];
        for (line in code.split("\n")) {
            var startChar = line.indexOf(marker);
            var endChar = line.lastIndexOf(marker);
            if (startChar != -1 && endChar != -1) {
                ranges.push({start: {line: lineNumber, character: startChar}, end: {line: lineNumber, character: endChar - 1}});
            }
            lineNumber++;
        }
        return ranges;
    }

    function testFindLocalVarUsages() {
        check("
class Foo {
    function foo() {
        var %bar%;
        %bar%;
    }
}");
    }
}