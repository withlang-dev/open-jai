#import "Basic";
#import "Hash_Table";

#run {
    table := New(Table(string, string));

    table_add(table, "John Smith", "521-8976");
    table_add(table, "Lisa Smith", "521-1234");
    table_add(table, "Sandra Dee", "521-9655");

    value, found := table_find(table, "Lisa Smith");
    missing, missing_found := table_find(table, "Jane Doe");
    table_remove(table, "Lisa Smith");
    removed, removed_found := table_find(table, "Lisa Smith");

    print("hash:% % % % %\n", found, value, missing_found, removed_found, removed);
}

main :: () {}
