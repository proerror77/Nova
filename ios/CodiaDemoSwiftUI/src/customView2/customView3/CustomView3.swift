//
//  CustomView3.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView3: View {
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
    @State public var text23Text: String = "view more"
    @State public var image31Path: String = "image31_4274"
    @State public var image32Path: String = "image32_4275"
    @State public var text24Text: String = "Simone Carter"
    @State public var text25Text: String = "1d"
    @State public var image33Path: String = "image33_4282"
    @State public var image34Path: String = "image34_4283"
    @State public var image35Path: String = "image35_4291"
    @State public var text26Text: String = "93"
    @State public var text27Text: String = "kyleegigstead Cyborg dreams"
    @State public var text28Text: String = "kyleegigstead Cyborg dreams"
    @State public var image36Path: String = "image36_4298"
    @State public var image37Path: String = "image37_4304"
    @State public var image38Path: String = "image38_4305"
    @State public var text29Text: String = "Simone Carter"
    @State public var text30Text: String = "1d"
    @State public var image39Path: String = "image39_4312"
    @State public var image40Path: String = "image40_4313"
    @State public var image41Path: String = "image41_4321"
    @State public var text31Text: String = "93"
    @State public var text32Text: String = "kyleegigstead Cyborg dreams"
    @State public var text33Text: String = "kyleegigstead Cyborg dreams"
    @State public var image42Path: String = "image42_4328"
    @State public var image43Path: String = "image43_4334"
    @State public var image44Path: String = "image44_4335"
    @State public var text34Text: String = "Simone Carter"
    @State public var text35Text: String = "1d"
    @State public var image45Path: String = "image45_4342"
    @State public var image46Path: String = "image46_4343"
    @State public var image47Path: String = "image47_4351"
    @State public var text36Text: String = "93"
    @State public var text37Text: String = "kyleegigstead Cyborg dreams"
    @State public var text38Text: String = "kyleegigstead Cyborg dreams"
    @State public var image48Path: String = "image48_4358"
    @State public var image49Path: String = "image49_4363"
    @State public var image50Path: String = "image50_4369"
    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color(red: 0.97, green: 0.96, blue: 0.96, opacity: 1.00))
                .frame(width: 393, height: 738)
            CustomView5(
                text1Text: text1Text,
                text2Text: text2Text,
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
                text22Text: text22Text,
                text23Text: text23Text,
                image31Path: image31Path,
                image32Path: image32Path,
                text24Text: text24Text,
                text25Text: text25Text,
                image33Path: image33Path,
                image34Path: image34Path,
                image35Path: image35Path,
                text26Text: text26Text,
                text27Text: text27Text,
                text28Text: text28Text,
                image36Path: image36Path,
                image37Path: image37Path,
                image38Path: image38Path,
                text29Text: text29Text,
                text30Text: text30Text,
                image39Path: image39Path,
                image40Path: image40Path,
                image41Path: image41Path,
                text31Text: text31Text,
                text32Text: text32Text,
                text33Text: text33Text,
                image42Path: image42Path,
                image43Path: image43Path,
                image44Path: image44Path,
                text34Text: text34Text,
                text35Text: text35Text,
                image45Path: image45Path,
                image46Path: image46Path,
                image47Path: image47Path,
                text36Text: text36Text,
                text37Text: text37Text,
                text38Text: text38Text,
                image48Path: image48Path,
                image49Path: image49Path,
                image50Path: image50Path)
                .frame(width: 393, height: 2609)
                .offset(y: -1957)
        }
        .frame(width: 393, height: 738, alignment: .topLeading)
        .clipped()
    }
}

struct CustomView3_Previews: PreviewProvider {
    static var previews: some View {
        CustomView3()
    }
}
