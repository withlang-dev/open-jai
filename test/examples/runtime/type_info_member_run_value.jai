#import "Basic";

Run_Info_Target :: struct {
    count: int;
    label: string;
}

first_member :: () -> Type_Info_Struct_Member {
    info := type_info(Run_Info_Target);
    return info.members[0];
}

member_name :: (member: Type_Info_Struct_Member) -> string {
    return member.name;
}

First_Member :: #run first_member();

#run {
    print("member:% type:% flags:% via:%\n", First_Member.name, type_to_string(First_Member.type), First_Member.flags, member_name(First_Member));
}

main :: () {}
