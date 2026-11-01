import {redirect} from "next/navigation";
import {readSession} from "@/lib/auth";
export const dynamic="force-dynamic";
export default async function Home(){const user=await readSession();if(!user)redirect("/login");redirect(`/${user.role.toLowerCase()}`)}
