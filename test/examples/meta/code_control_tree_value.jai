#import "Basic";
#import "Compiler";

code :: #code {
    if ready {
        return 41 + 1;
    }
    while ready {
        step();
    }
    for items {
        total += it;
    }
};

#run {
    root, expressions := compiler_get_nodes(code);
    print("root kind: %\n", root.kind);
    print("root subexpressions: %\n", root.subexpressions.count);
    for expr : expressions {
        print("kind: % subexpressions: %\n", expr.kind, expr.subexpressions.count);
    }
}

main :: () {}
