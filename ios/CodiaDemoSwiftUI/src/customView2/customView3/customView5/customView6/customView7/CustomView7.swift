//
//  CustomView7.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView7: View {
    @State public var text1Text: String = "Hottest Banker in H.K."
    @State public var text2Text: String = "Corporate Poll"
    @State public var image1Path: String = "image1_I426841881"
    @State public var text3Text: String = "1"
    @State public var text4Text: String = "Lucy Liu"
    @State public var text5Text: String = "Morgan Stanley"
    @State public var text6Text: String = "2293"
    @State public var image7Path: String = "image7_I426841901"
    @State public var text7Text: String = "2"
    @State public var text8Text: String = "Lucy Liu"
    @State public var text9Text: String = "Morgan Stanley"
    @State public var text10Text: String = "2293"
    @State public var image13Path: String = "image13_I426841921"
    @State public var text11Text: String = "3"
    @State public var text12Text: String = "Lucy Liu"
    @State public var text13Text: String = "Morgan Stanley"
    @State public var text14Text: String = "2293"
    @State public var image19Path: String = "image19_I426841941"
    @State public var text15Text: String = "4"
    @State public var text16Text: String = "Lucy Liu"
    @State public var text17Text: String = "Morgan Stanley"
    @State public var text18Text: String = "2293"
    @State public var image25Path: String = "image25_I426841961"
    @State public var text19Text: String = "5"
    @State public var text20Text: String = "Lucy Liu"
    @State public var text21Text: String = "Morgan Stanley"
    @State public var text22Text: String = "2293"
    var body: some View {
        ZStack(alignment: .topLeading) {
            CustomView8(
                text1Text: text1Text,
                text2Text: text2Text)
                .frame(width: 272.694, height: 38)
                .offset(x: 60.153)
            CustomView9(
                image1Path: image1Path,
                text3Text: text3Text,
                text4Text: text4Text,
                text5Text: text5Text,
                text6Text: text6Text,
                image7Path: image7Path,
                text7Text: text7Text,
                text8Text: text8Text,
                text9Text: text9Text,
                text10Text: text10Text,
                image13Path: image13Path,
                text11Text: text11Text,
                text12Text: text12Text,
                text13Text: text13Text,
                text14Text: text14Text,
                image19Path: image19Path,
                text15Text: text15Text,
                text16Text: text16Text,
                text17Text: text17Text,
                text18Text: text18Text,
                image25Path: image25Path,
                text19Text: text19Text,
                text20Text: text20Text,
                text21Text: text21Text,
                text22Text: text22Text)
                .frame(width: 393, height: 392)
                .offset(y: 56)
        }
        .frame(width: 393, height: 448, alignment: .topLeading)
    }
}

struct CustomView7_Previews: PreviewProvider {
    static var previews: some View {
        CustomView7()
    }
}
