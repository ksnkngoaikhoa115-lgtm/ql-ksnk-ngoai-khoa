import './globals.css';
import './report-responsive.css';
import './task.css';
import './login.css';
import type { Metadata, Viewport } from 'next';
// Desktop layout on touch devices: browser fits the wide layout and permits native pinch zoom.
export const viewport: Viewport={width:1280,initialScale:undefined,userScalable:true};
export const metadata: Metadata={title:'QL KSNK Ngoại Khoa',description:'Quản lý KSNK Ngoại Khoa'};
export default function RootLayout({children}:{children:React.ReactNode}){return <html lang="vi"><body>{children}</body></html>}
